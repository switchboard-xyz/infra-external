#!/usr/bin/env python3
"""Record an exact, no-rollout Helm baseline for one allowlisted devnet host.

The command renders the existing release with explicit immutable images and
live replica counts, asks the API server to dry-run the rendered resources,
and refuses to create a Helm revision unless every protected spec is already
equivalent. Helm's Secret driver necessarily reads and decodes its own release
metadata internally. Stored manifests are streamed by document kind; Secret
and unrelated document bodies are discarded rather than retained or parsed.
This wrapper never requests Kubernetes workload Secret objects, exposes Secret
payloads, or prints Helm release values, Secret references, confidential-
container policy contents, manifests, or command output. The host-local lock
serializes cooperating invocations of this tool;
it cannot fence an unrelated actor that bypasses the lock, so a root-coordinator
exclusive-window assertion remains mandatory.
"""

from __future__ import annotations

import argparse
import copy
from decimal import Decimal, InvalidOperation
import fcntl
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
CHART_DIR = SCRIPT_DIR.parent / "helm" / "charts" / "on-demand"
DEVNET_NAMESPACE = "switchboard-oracle-devnet"
DEVNET_RELEASE = "sb-oracle-devnet"
COMPONENTS = ("oracle", "guardian", "gateway")
COMPONENT_REPOSITORIES = {
    component: f"docker.io/switchboardlabs/{component}" for component in COMPONENTS
}
AUTHORIZED_HOSTS = {
    "stra01": "ovh-stra-01",
    "rbx01": "ovh-rbx-01",
}
DIGEST_PATTERN = re.compile(r"sha256:[a-f0-9]{64}")
SECRET_KIND_PATTERN = re.compile(r"(?m)^kind:[ \t]*Secret[ \t]*$")
CC_INIT_DATA_ANNOTATION = "io.katacontainers.config.runtime.cc_init_data"
KEEL_UPDATE_TIME_ANNOTATION = "keel.sh/update-time"
ORACLE_KEEL_DEPLOYMENT_ANNOTATIONS = {
    "keel.sh/approvals": "0",
    "keel.sh/trigger": "poll",
    "keel.sh/match-tag": "true",
    "keel.sh/policy": "force",
}
HELM_RELEASE_NAME_ANNOTATION = "meta.helm.sh/release-name"
HELM_RELEASE_NAMESPACE_ANNOTATION = "meta.helm.sh/release-namespace"
HELM_MANAGED_BY_LABEL = "app.kubernetes.io/managed-by"
DEPLOYMENT_REVISION_ANNOTATION = "deployment.kubernetes.io/revision"
KUBERNETES_CHANGE_CAUSE_ANNOTATION = "kubernetes.io/change-cause"
ALLOWED_RENDERED_KINDS = {"Deployment", "Service", "Ingress"}
KUBECTL_LAST_APPLIED_ANNOTATION = "kubectl.kubernetes.io/last-applied-configuration"
OPERATION_LOCK_PATH = Path("/run/lock/switchboard-oracle-devnet-helm-baseline.lock")


class BaselineError(Exception):
    """A fail-closed validation or execution error."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate or record an exact devnet Helm rollback baseline."
    )
    parser.add_argument("--network", required=True)
    parser.add_argument("--host-id", required=True)
    parser.add_argument(
        "--expected-current-oracle-image",
        required=True,
        help="Exact immutable Oracle image confirmed by the operator.",
    )
    parser.add_argument(
        "--coordinator-exclusive-window-confirmed",
        action="store_true",
        required=True,
        help=(
            "Assert that the root coordinator has granted an exclusive host-operation "
            "window for this complete plan/apply invocation."
        ),
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Record the validated Helm baseline revision after every gate passes.",
    )
    parser.add_argument(
        "--disable-oracle-keel-deployment-annotations",
        action="store_true",
        help=(
            "Use the rbx01-devnet-only Oracle Keel Deployment annotation "
            "opt-out after the live annotations were removed explicitly."
        ),
    )
    return parser.parse_args()


def require_mapping(parent: dict[str, Any], key: str, label: str) -> dict[str, Any]:
    value = parent.get(key)
    if not isinstance(value, dict):
        raise BaselineError(f"{label} is missing or invalid")
    return value


def require_list(parent: dict[str, Any], key: str, label: str) -> list[Any]:
    value = parent.get(key)
    if not isinstance(value, list):
        raise BaselineError(f"{label} is missing or invalid")
    return value


def canonical_hash(value: Any) -> str:
    payload = json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=True
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def acquire_operation_lock() -> int:
    if not hasattr(os, "O_NOFOLLOW"):
        raise BaselineError("host-local operation lock is unavailable")
    try:
        descriptor = os.open(
            OPERATION_LOCK_PATH,
            os.O_RDWR | os.O_CREAT | os.O_CLOEXEC | os.O_NOFOLLOW,
            0o600,
        )
    except OSError as error:
        raise BaselineError("host-local operation lock is unavailable") from error
    try:
        metadata = os.fstat(descriptor)
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_uid != os.geteuid()
            or metadata.st_mode & 0o022
        ):
            raise BaselineError("host-local operation lock is not authoritative")
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise BaselineError("another coordinated baseline operation holds the lock") from error
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def release_operation_lock(descriptor: int) -> None:
    try:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
    finally:
        os.close(descriptor)


def run_command(
    command: list[str],
    *,
    input_text: str | None = None,
    accepted_codes: set[int] | None = None,
    error_message: str,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command,
        input=input_text,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    allowed = accepted_codes if accepted_codes is not None else {0}
    if result.returncode not in allowed:
        raise BaselineError(error_message)
    return result


def run_kubectl(
    arguments: list[str],
    *,
    context: str | None = None,
    input_text: str | None = None,
    error_message: str = "kubectl command failed",
) -> str:
    command = ["kubectl"]
    if context is not None:
        command.extend(["--context", context])
    command.extend(arguments)
    return run_command(
        command, input_text=input_text, error_message=error_message
    ).stdout


def run_helm(
    arguments: list[str], *, error_message: str = "Helm command failed"
) -> str:
    return run_command(["helm", *arguments], error_message=error_message).stdout


def run_helm_protected_manifest(arguments: list[str]) -> str:
    process = subprocess.Popen(
        ["helm", *arguments],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    if process.stdout is None:
        process.kill()
        process.wait()
        raise BaselineError("stored Helm release manifest lookup failed")

    retained_documents: list[str] = []
    header: list[str] = []
    retained: list[str] | None = None
    document_kind: str | None = None
    metadata_started = False
    identity_resolved = False

    def finish_document() -> None:
        nonlocal header, retained, document_kind, metadata_started, identity_resolved
        if document_kind in ALLOWED_RENDERED_KINDS and not identity_resolved:
            raise BaselineError("stored Helm manifest resource identity is unsafe")
        if retained is not None:
            retained_documents.append("".join(retained))
        header = []
        retained = None
        document_kind = None
        metadata_started = False
        identity_resolved = False

    try:
        for line in process.stdout:
            if line.strip() == "---":
                finish_document()
                continue
            if document_kind is None:
                if re.match(r"^(?:data|stringData|binaryData):(?:[ \t]|$)", line):
                    raise BaselineError("stored Helm manifest kind header is unsafe")
                header.append(line)
                match = re.match(r"^kind:[ \t]*['\"]?([^'\" \t\r\n]+)", line)
                if match is None:
                    continue
                document_kind = match.group(1)
                if document_kind not in ALLOWED_RENDERED_KINDS:
                    header = []
                    identity_resolved = True
                continue
            if not identity_resolved:
                if re.match(r"^(?:data|stringData|binaryData):(?:[ \t]|$)", line):
                    raise BaselineError("stored Helm manifest resource identity is unsafe")
                header.append(line)
                if re.match(r"^metadata:[ \t]*(?:#.*)?$", line):
                    metadata_started = True
                    continue
                name_match = (
                    re.match(r"^[ \t]+name:[ \t]*['\"]?([^'\" \t\r\n]+)", line)
                    if metadata_started
                    else None
                )
                if name_match is not None:
                    identity_resolved = True
                    if name_match.group(1) in COMPONENTS:
                        retained = list(header)
                    else:
                        header = []
                    continue
                if metadata_started and re.match(r"^[A-Za-z]", line):
                    raise BaselineError("stored Helm manifest resource identity is unsafe")
                continue
            if retained is not None:
                retained.append(line)
        finish_document()
    except BaseException:
        process.kill()
        process.wait()
        raise
    return_code = process.wait()
    if return_code != 0:
        raise BaselineError("stored Helm release manifest lookup failed")
    if not retained_documents:
        raise BaselineError("stored Helm release manifest returned no protected resources")
    return "\n---\n".join(retained_documents)


def parse_json_object(output: str, label: str) -> dict[str, Any]:
    try:
        value = json.loads(output)
    except json.JSONDecodeError as error:
        raise BaselineError(f"{label} returned invalid JSON") from error
    if not isinstance(value, dict):
        raise BaselineError(f"{label} returned an invalid object")
    return value


def parse_json_documents(output: str, label: str) -> list[dict[str, Any]]:
    decoder = json.JSONDecoder()
    offset = 0
    documents: list[dict[str, Any]] = []
    while offset < len(output):
        while offset < len(output) and output[offset].isspace():
            offset += 1
        if offset == len(output):
            break
        try:
            value, offset = decoder.raw_decode(output, offset)
        except json.JSONDecodeError as error:
            raise BaselineError(f"{label} returned invalid JSON") from error
        if not isinstance(value, dict):
            raise BaselineError(f"{label} returned an invalid resource")
        if value.get("kind") == "List":
            items = value.get("items")
            if not isinstance(items, list) or not all(
                isinstance(item, dict) for item in items
            ):
                raise BaselineError(f"{label} returned an invalid resource list")
            documents.extend(items)
        else:
            documents.append(value)
    if not documents:
        raise BaselineError(f"{label} returned no resources")
    return documents


def validate_target(
    network: str,
    host_id: str,
    disable_oracle_keel_deployment_annotations: bool,
) -> str:
    if network != "devnet":
        raise BaselineError("Helm baseline creation is devnet-only")
    node_name = AUTHORIZED_HOSTS.get(host_id)
    if node_name is None:
        raise BaselineError("unknown or excluded devnet host ID")
    if disable_oracle_keel_deployment_annotations and host_id != "rbx01":
        raise BaselineError(
            "Oracle Keel Deployment annotation opt-out is restricted to rbx01 devnet"
        )
    return node_name


def validate_tool_capabilities() -> None:
    for command_name in ("helm", "kubectl"):
        if shutil.which(command_name) is None:
            raise BaselineError(f"required command is unavailable: {command_name}")
    if not CHART_DIR.is_dir():
        raise BaselineError("the on-demand Helm chart is unavailable")
    if os.environ.get("HELM_DRIVER", "secret") != "secret":
        raise BaselineError("the exact Helm release must use Secret metadata storage")

    helm_help = run_helm(["upgrade", "--help"], error_message="Helm help failed")
    for required_fragment in (
        "--dry-run",
        "client",
        "server",
        "--hide-secret",
        "--history-max",
        "--reuse-values",
        "--no-hooks",
    ):
        if required_fragment not in helm_help:
            raise BaselineError("Helm lacks a required safe-upgrade capability")

    kubectl_help = run_kubectl(
        ["apply", "--help"], error_message="kubectl help failed"
    )
    for required_fragment in ("--dry-run", "server"):
        if required_fragment not in kubectl_help:
            raise BaselineError("kubectl lacks a required server dry-run capability")
    kubectl_create_help = run_kubectl(
        ["create", "--help"], error_message="kubectl help failed"
    )
    for required_fragment in ("--dry-run", "client"):
        if required_fragment not in kubectl_create_help:
            raise BaselineError("kubectl lacks a required client parse capability")


def validate_cluster_identity(context: str, node_name: str) -> None:
    nodes = parse_json_object(
        run_kubectl(
            ["get", "nodes", "--output=json"],
            context=context,
            error_message="node identity lookup failed",
        ),
        "node identity lookup",
    )
    if nodes.get("apiVersion") != "v1" or nodes.get("kind") not in {
        "List",
        "NodeList",
    }:
        raise BaselineError("target context returned an invalid Node list")
    items = nodes.get("items")
    if not isinstance(items, list) or len(items) != 1:
        raise BaselineError("target context must contain exactly one Kubernetes node")
    metadata = items[0].get("metadata") if isinstance(items[0], dict) else None
    if not isinstance(metadata, dict) or metadata.get("name") != node_name:
        raise BaselineError("target context node does not match the selected host")


def parse_list(output: str, label: str) -> list[dict[str, Any]]:
    value = parse_json_object(output, label)
    kind = value.get("kind")
    if not isinstance(kind, str) or not kind.endswith("List"):
        raise BaselineError(f"{label} returned an invalid list")
    items = value.get("items")
    if not isinstance(items, list) or not all(isinstance(item, dict) for item in items):
        raise BaselineError(f"{label} returned invalid list items")
    return items


def fetch_resources(context: str) -> dict[tuple[str, str], dict[str, Any]]:
    requests = (
        ("deployment", "Deployment", False),
        ("service", "Service", False),
        ("ingress", "Ingress", True),
    )
    resources: dict[tuple[str, str], dict[str, Any]] = {}
    for resource_type, expected_kind, ignore_not_found in requests:
        arguments = [
            "--namespace",
            DEVNET_NAMESPACE,
            "get",
            resource_type,
            *COMPONENTS,
            "--output=json",
        ]
        if ignore_not_found:
            arguments.append("--ignore-not-found")
        items = parse_list(
            run_kubectl(
                arguments,
                context=context,
                error_message="protected resource lookup failed",
            ),
            "protected resource lookup",
        )
        for item in items:
            metadata = item.get("metadata")
            name = metadata.get("name") if isinstance(metadata, dict) else None
            namespace = metadata.get("namespace") if isinstance(metadata, dict) else None
            if (
                item.get("kind") != expected_kind
                or name not in COMPONENTS
                or namespace != DEVNET_NAMESPACE
            ):
                raise BaselineError("protected resource identity is invalid")
            key = (expected_kind, name)
            if key in resources:
                raise BaselineError("protected resource lookup returned a duplicate")
            resources[key] = item

    for component in COMPONENTS:
        for kind in ("Deployment", "Service"):
            if (kind, component) not in resources:
                raise BaselineError("a required protected resource is absent")
    return resources


def validate_helm_ownership(resource: dict[str, Any]) -> None:
    metadata = require_mapping(resource, "metadata", "resource metadata")
    annotations = require_mapping(metadata, "annotations", "resource annotations")
    labels = require_mapping(metadata, "labels", "resource labels")
    if (
        annotations.get(HELM_RELEASE_NAME_ANNOTATION) != DEVNET_RELEASE
        or annotations.get(HELM_RELEASE_NAMESPACE_ANNOTATION) != DEVNET_NAMESPACE
        or labels.get(HELM_MANAGED_BY_LABEL) != "Helm"
    ):
        raise BaselineError("protected resource is not owned by the exact devnet release")


def component_container(deployment: dict[str, Any], component: str) -> dict[str, Any]:
    spec = require_mapping(deployment, "spec", "Deployment spec")
    template = require_mapping(spec, "template", "Deployment template")
    pod_spec = require_mapping(template, "spec", "Deployment pod spec")
    containers = require_list(pod_spec, "containers", "Deployment containers")
    matches = [
        container
        for container in containers
        if isinstance(container, dict) and container.get("name") == component
    ]
    if len(matches) != 1:
        raise BaselineError("Deployment does not contain exactly one component container")
    return matches[0]


def parse_immutable_image(component: str, image: Any) -> tuple[str, str]:
    repository = COMPONENT_REPOSITORIES[component]
    prefix = f"{repository}@"
    if not isinstance(image, str) or not image.startswith(prefix):
        raise BaselineError("component image is not pinned to its authorized repository")
    digest = image.removeprefix(prefix)
    if DIGEST_PATTERN.fullmatch(digest) is None:
        raise BaselineError("component image is not pinned to an immutable digest")
    return repository, digest


def matching_env(container: dict[str, Any], name: str) -> list[dict[str, Any]]:
    env = require_list(container, "env", "container environment")
    return [
        item for item in env if isinstance(item, dict) and item.get("name") == name
    ]


def secret_reference(item: dict[str, Any], label: str) -> tuple[str, str, bool | None]:
    if "value" in item:
        raise BaselineError(f"{label} must not be a literal value")
    value_from = require_mapping(item, "valueFrom", f"{label} value source")
    reference = require_mapping(
        value_from, "secretKeyRef", f"{label} Secret reference"
    )
    name = reference.get("name")
    key = reference.get("key")
    optional = reference.get("optional")
    if not isinstance(name, str) or not name or not isinstance(key, str) or not key:
        raise BaselineError(f"{label} Secret reference is invalid")
    if optional not in (None, False, True):
        raise BaselineError(f"{label} Secret optional state is invalid")
    return name, key, optional


def env_literal(container: dict[str, Any], name: str) -> str:
    matches = matching_env(container, name)
    if len(matches) != 1 or not isinstance(matches[0].get("value"), str):
        raise BaselineError(f"{name} environment identity is invalid")
    if "valueFrom" in matches[0]:
        raise BaselineError(f"{name} environment identity is invalid")
    return matches[0]["value"]


def optional_env_literal(container: dict[str, Any], name: str) -> str | None:
    matches = matching_env(container, name)
    if not matches:
        return None
    if len(matches) != 1 or not isinstance(matches[0].get("value"), str):
        raise BaselineError(f"{name} environment identity is invalid")
    if "valueFrom" in matches[0]:
        raise BaselineError(f"{name} environment identity is invalid")
    return matches[0]["value"]


def optional_environment_secret(
    container: dict[str, Any],
) -> tuple[str, bool | None] | None:
    if "envFrom" not in container:
        return None
    sources = require_list(container, "envFrom", "Oracle environment sources")
    if len(sources) != 1 or not isinstance(sources[0], dict):
        raise BaselineError("Oracle environment source cannot be reproduced by this chart")
    if set(sources[0]) != {"secretRef"}:
        raise BaselineError("Oracle environment source cannot be reproduced by this chart")
    reference = require_mapping(
        sources[0], "secretRef", "Oracle environment Secret reference"
    )
    if not set(reference).issubset({"name", "optional"}):
        raise BaselineError("Oracle environment Secret reference is invalid")
    name = reference.get("name")
    optional = reference.get("optional")
    if not isinstance(name, str) or not name or optional not in (None, False, True):
        raise BaselineError("Oracle environment Secret reference is invalid")
    return name, optional


def replica_count(deployment: dict[str, Any], component: str) -> int:
    spec = require_mapping(deployment, "spec", "Deployment spec")
    replicas = spec.get("replicas")
    if isinstance(replicas, bool) or not isinstance(replicas, int) or replicas < 0:
        raise BaselineError("Deployment replica count is invalid")
    if component == "oracle" and replicas == 0:
        raise BaselineError("Oracle replicas=0 is excluded from baseline creation")
    return replicas


def validate_live_resources(
    resources: dict[tuple[str, str], dict[str, Any]],
    expected_oracle_image: str,
    disable_oracle_keel_deployment_annotations: bool,
) -> dict[str, Any]:
    for resource in resources.values():
        validate_helm_ownership(resource)

    if disable_oracle_keel_deployment_annotations:
        oracle_metadata = require_mapping(
            resources[("Deployment", "oracle")],
            "metadata",
            "Oracle Deployment metadata",
        )
        oracle_annotations = require_mapping(
            oracle_metadata,
            "annotations",
            "Oracle Deployment annotations",
        )
        if any(
            key in oracle_annotations
            for key in ORACLE_KEEL_DEPLOYMENT_ANNOTATIONS
        ):
            raise BaselineError(
                "Oracle Keel Deployment annotations must already be absent"
            )

    images: dict[str, dict[str, str]] = {}
    replicas: dict[str, int] = {}
    resource_requirements: dict[str, dict[str, dict[str, str]]] = {}
    policies: dict[str, str] = {}
    payer_refs: dict[str, tuple[str, str, bool | None]] = {}
    sui_ref: tuple[str, str, bool | None] | None = None
    candle_collection: str | None = None
    environment_secret: tuple[str, bool | None] | None = None
    oracle_keel_update_time: str | None = None

    for component in COMPONENTS:
        deployment = resources[("Deployment", component)]
        deployment_spec = require_mapping(deployment, "spec", "Deployment spec")
        selector = require_mapping(deployment_spec, "selector", "Deployment selector")
        match_labels = require_mapping(
            selector, "matchLabels", "Deployment selector labels"
        )
        template = require_mapping(
            deployment_spec, "template", "Deployment template"
        )
        template_metadata = require_mapping(
            template, "metadata", "Deployment template metadata"
        )
        template_labels = require_mapping(
            template_metadata, "labels", "Deployment template labels"
        )
        if (
            match_labels.get("app") != component
            or template_labels.get("app") != component
        ):
            raise BaselineError("Deployment selector identity is invalid")
        container = component_container(deployment, component)
        repository, digest = parse_immutable_image(component, container.get("image"))
        images[component] = {"repository": repository, "digest": digest}
        replicas[component] = replica_count(deployment, component)
        requirements = require_mapping(
            container, "resources", "Deployment resource requirements"
        )
        normalized_requirements: dict[str, dict[str, str]] = {}
        for requirement_kind in ("limits", "requests"):
            requirement_values = require_mapping(
                requirements,
                requirement_kind,
                "Deployment resource requirements",
            )
            if set(requirement_values) != {"cpu", "memory"} or not all(
                isinstance(requirement_values[name], str)
                and requirement_values[name]
                for name in ("cpu", "memory")
            ):
                raise BaselineError("Deployment resource requirements are invalid")
            normalized_requirements[requirement_kind] = {
                name: requirement_values[name] for name in ("cpu", "memory")
            }
        resource_requirements[component] = normalized_requirements
        if env_literal(container, "NETWORK_ID") != "devnet":
            raise BaselineError("Deployment network identity is not devnet")

        payer = matching_env(container, "PAYER_SECRET")
        if len(payer) != 1:
            raise BaselineError("PAYER_SECRET environment identity is invalid")
        payer_refs[component] = secret_reference(payer[0], "PAYER_SECRET")

        sui = matching_env(container, "SUI_MAINNET_RPC")
        if component == "oracle":
            if len(sui) > 1:
                raise BaselineError("SUI_MAINNET_RPC environment identity is invalid")
            if sui:
                sui_ref = secret_reference(sui[0], "SUI_MAINNET_RPC")
            candle_collection = optional_env_literal(
                container, "CANDLE_COLLECTION_ENABLED"
            )
            environment_secret = optional_environment_secret(container)
        elif sui:
            raise BaselineError("SUI_MAINNET_RPC is present on an unexpected component")

        annotations = require_mapping(
            template_metadata, "annotations", "Deployment template annotations"
        )
        if KEEL_UPDATE_TIME_ANNOTATION in annotations:
            update_time = annotations[KEEL_UPDATE_TIME_ANNOTATION]
            if component != "oracle" or not isinstance(update_time, str):
                raise BaselineError(
                    "Oracle keel update-time annotation state is invalid"
                )
            oracle_keel_update_time = update_time
        policy = annotations.get(CC_INIT_DATA_ANNOTATION)
        if policy is None:
            policies[component] = ""
        elif isinstance(policy, str) and policy:
            policies[component] = policy
        else:
            raise BaselineError("confidential-container policy state is invalid")

    oracle_image = (
        f'{images["oracle"]["repository"]}@{images["oracle"]["digest"]}'
    )
    if expected_oracle_image != oracle_image:
        raise BaselineError(
            "live Oracle image differs from the operator-confirmed immutable image"
        )

    payer_values = set(payer_refs.values())
    if len(payer_values) != 1:
        raise BaselineError("payer Secret references differ between components")
    payer_name, payer_key, payer_optional = next(iter(payer_values))
    if payer_name != "payer-secret" or payer_optional not in (None, False):
        raise BaselineError("payer Secret reference cannot be reproduced by this chart")

    present_policies = [bool(policies[component]) for component in COMPONENTS]
    if any(present_policies) and not all(present_policies):
        raise BaselineError(
            "confidential-container policy state must be present on all components or none"
        )

    return {
        "images": images,
        "replicas": replicas,
        "resources": resource_requirements,
        "policies": policies,
        "payerKey": payer_key,
        "suiRef": sui_ref,
        "candleCollection": candle_collection,
        "environmentSecret": environment_secret,
        "oracleKeelUpdateTime": oracle_keel_update_time,
    }


def resource_specs(
    resources: dict[tuple[str, str], dict[str, Any]]
) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for (kind, name), resource in sorted(resources.items()):
        spec = resource.get("spec")
        if not isinstance(spec, dict):
            raise BaselineError("protected resource spec is missing or invalid")
        result[f"{kind}/{name}"] = spec
    return result


def resource_metadata_contract(
    resources: dict[tuple[str, str], dict[str, Any]]
) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for (kind, name), resource in sorted(resources.items()):
        metadata = require_mapping(resource, "metadata", "resource metadata")
        labels = metadata.get("labels", {})
        annotations = metadata.get("annotations", {})
        if not isinstance(labels, dict) or not isinstance(annotations, dict):
            raise BaselineError("protected resource metadata is invalid")
        filtered_annotations = {
            key: value
            for key, value in annotations.items()
            if key != KUBECTL_LAST_APPLIED_ANNOTATION
        }
        result[f"{kind}/{name}"] = {
            "labels": labels,
            "annotations": filtered_annotations,
        }
    return result


_MISSING_METADATA_VALUE = object()


def metadata_value_equal(left: Any, right: Any) -> bool:
    if left is _MISSING_METADATA_VALUE or right is _MISSING_METADATA_VALUE:
        return left is right
    return type(left) is type(right) and left == right


def allowed_live_only_metadata(
    kind: str,
    section: str,
    key: str,
    value: Any,
) -> bool:
    if section == "labels":
        return key == HELM_MANAGED_BY_LABEL and value == "Helm"
    if section != "annotations":
        return False
    if key == HELM_RELEASE_NAME_ANNOTATION:
        return value == DEVNET_RELEASE
    if key == HELM_RELEASE_NAMESPACE_ANNOTATION:
        return value == DEVNET_NAMESPACE
    if kind != "Deployment":
        return False
    if key == KUBERNETES_CHANGE_CAUSE_ANNOTATION:
        return isinstance(value, str)
    return key == DEPLOYMENT_REVISION_ANNOTATION and (
        isinstance(value, str)
        and re.fullmatch(r"[1-9][0-9]*", value) is not None
    )


def require_change_cause_live_only_contract(
    live: dict[tuple[str, str], dict[str, Any]],
    stored: dict[tuple[str, str], dict[str, Any]],
    rendered: dict[tuple[str, str], dict[str, Any]],
    candidate_label: str,
) -> None:
    if set(live) != set(stored) or set(live) != set(rendered):
        raise BaselineError(f"{candidate_label} resource set differs from live")
    live_contract = resource_metadata_contract(live)
    stored_contract = resource_metadata_contract(stored)
    rendered_contract = resource_metadata_contract(rendered)
    for kind, name in sorted(live):
        identity = f"{kind}/{name}"
        live_annotations = live_contract[identity]["annotations"]
        stored_annotations = stored_contract[identity]["annotations"]
        rendered_annotations = rendered_contract[identity]["annotations"]
        live_value = live_annotations.get(
            KUBERNETES_CHANGE_CAUSE_ANNOTATION,
            _MISSING_METADATA_VALUE,
        )
        stored_value = stored_annotations.get(
            KUBERNETES_CHANGE_CAUSE_ANNOTATION,
            _MISSING_METADATA_VALUE,
        )
        rendered_value = rendered_annotations.get(
            KUBERNETES_CHANGE_CAUSE_ANNOTATION,
            _MISSING_METADATA_VALUE,
        )
        if (
            live_value is _MISSING_METADATA_VALUE
            and stored_value is _MISSING_METADATA_VALUE
            and rendered_value is _MISSING_METADATA_VALUE
        ):
            continue
        if (
            kind != "Deployment"
            or stored_value is not _MISSING_METADATA_VALUE
            or rendered_value is not _MISSING_METADATA_VALUE
            or not isinstance(live_value, str)
        ):
            raise BaselineError(
                f"{candidate_label} contains unsupported kubernetes.io/change-cause metadata"
            )


def metadata_three_way_preservation_proof(
    live: dict[tuple[str, str], dict[str, Any]],
    stored: dict[tuple[str, str], dict[str, Any]],
    candidate: dict[tuple[str, str], dict[str, Any]],
    candidate_label: str,
) -> str:
    if set(live) != set(stored) or set(live) != set(candidate):
        raise BaselineError(f"{candidate_label} resource set differs from live")

    live_contract = resource_metadata_contract(live)
    stored_contract = resource_metadata_contract(stored)
    candidate_contract = resource_metadata_contract(candidate)
    preserved_live_only_paths: list[str] = []

    for kind, name in sorted(live):
        identity = f"{kind}/{name}"
        for section in ("labels", "annotations"):
            live_values = live_contract[identity][section]
            stored_values = stored_contract[identity][section]
            candidate_values = candidate_contract[identity][section]
            for key in sorted(
                set(live_values) | set(stored_values) | set(candidate_values)
            ):
                live_value = live_values.get(key, _MISSING_METADATA_VALUE)
                stored_value = stored_values.get(key, _MISSING_METADATA_VALUE)
                candidate_value = candidate_values.get(
                    key, _MISSING_METADATA_VALUE
                )
                if metadata_value_equal(live_value, candidate_value):
                    continue
                path = f"{identity}/metadata/{section}/{key}"
                if (
                    candidate_value is _MISSING_METADATA_VALUE
                    and stored_value is _MISSING_METADATA_VALUE
                    and live_value is not _MISSING_METADATA_VALUE
                    and allowed_live_only_metadata(
                        kind, section, key, live_value
                    )
                ):
                    preserved_live_only_paths.append(path)
                    continue
                raise BaselineError(
                    f"{candidate_label} would change protected resource metadata"
                )

    return canonical_hash(
        {
            "live": live_contract,
            "preservedLiveOnlyPaths": preserved_live_only_paths,
        }
    )


def pod_templates(
    resources: dict[tuple[str, str], dict[str, Any]]
) -> dict[str, Any]:
    return {
        component: require_mapping(
            require_mapping(
                resources[("Deployment", component)], "spec", "Deployment spec"
            ),
            "template",
            "Deployment template",
        )
        for component in COMPONENTS
    }


def pod_template_annotations(
    resources: dict[tuple[str, str], dict[str, Any]]
) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for component in COMPONENTS:
        deployment = resources[("Deployment", component)]
        deployment_spec = require_mapping(deployment, "spec", "Deployment spec")
        template = require_mapping(
            deployment_spec, "template", "Deployment template"
        )
        template_metadata = require_mapping(
            template, "metadata", "Deployment template metadata"
        )
        result[component] = require_mapping(
            template_metadata,
            "annotations",
            "Deployment template annotations",
        )
    return result


def replicas_map(
    resources: dict[tuple[str, str], dict[str, Any]]
) -> dict[str, int]:
    return {
        component: replica_count(resources[("Deployment", component)], component)
        for component in COMPONENTS
    }


def collect_secret_references(value: Any, path: tuple[str, ...] = ()) -> list[Any]:
    result: list[Any] = []
    if isinstance(value, dict):
        for key in sorted(value):
            child = value[key]
            child_path = (*path, key)
            if key == "secretKeyRef":
                if not isinstance(child, dict):
                    raise BaselineError("rendered Secret reference is invalid")
                name = child.get("name")
                secret_key = child.get("key")
                optional = child.get("optional")
                if (
                    not isinstance(name, str)
                    or not name
                    or not isinstance(secret_key, str)
                    or not secret_key
                    or optional not in (None, False, True)
                ):
                    raise BaselineError("rendered Secret reference is invalid")
                result.append(
                    {
                        "path": list(child_path),
                        "name": name,
                        "key": secret_key,
                        "optional": optional,
                    }
                )
            elif key == "secretRef":
                if not isinstance(child, dict):
                    raise BaselineError("rendered Secret reference is invalid")
                name = child.get("name")
                optional = child.get("optional")
                if (
                    not isinstance(name, str)
                    or not name
                    or optional not in (None, False, True)
                    or not set(child).issubset({"name", "optional"})
                ):
                    raise BaselineError("rendered Secret reference is invalid")
                result.append(
                    {
                        "path": list(child_path),
                        "name": name,
                        "optional": optional,
                    }
                )
            else:
                result.extend(collect_secret_references(child, child_path))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            result.extend(collect_secret_references(child, (*path, str(index))))
    return result


def resource_version_guard(
    resources: dict[tuple[str, str], dict[str, Any]]
) -> dict[str, str]:
    result: dict[str, str] = {}
    for (kind, name), resource in sorted(resources.items()):
        metadata = require_mapping(resource, "metadata", "resource metadata")
        resource_version = metadata.get("resourceVersion")
        if not isinstance(resource_version, str) or not resource_version:
            raise BaselineError("protected resource resourceVersion is missing")
        result[f"{kind}/{name}"] = resource_version
    return result


def nonvolatile_resource_metadata(
    resources: dict[tuple[str, str], dict[str, Any]],
    *,
    ignore_oracle_deployment_generation: bool = False,
) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for (kind, name), resource in sorted(resources.items()):
        metadata = copy.deepcopy(
            require_mapping(resource, "metadata", "resource metadata")
        )
        metadata.pop("resourceVersion", None)
        if (
            ignore_oracle_deployment_generation
            and kind == "Deployment"
            and name == "oracle"
        ):
            metadata.pop("generation", None)
        metadata.pop("managedFields", None)
        annotations = metadata.get("annotations", {})
        if not isinstance(annotations, dict):
            raise BaselineError("protected resource metadata is invalid")
        annotations.pop(KUBECTL_LAST_APPLIED_ANNOTATION, None)
        result[f"{kind}/{name}"] = metadata
    return result


def deployment_generation_guard(
    resources: dict[tuple[str, str], dict[str, Any]]
) -> dict[str, int]:
    result: dict[str, int] = {}
    for component in COMPONENTS:
        metadata = require_mapping(
            resources[("Deployment", component)],
            "metadata",
            "Deployment metadata",
        )
        generation = metadata.get("generation")
        if (
            isinstance(generation, bool)
            or not isinstance(generation, int)
            or generation < 1
        ):
            raise BaselineError("Deployment generation is missing or invalid")
        result[component] = generation
    return result


def fetch_pod_snapshot(
    context: str, node_name: str, replicas: dict[str, int]
) -> dict[str, Any]:
    snapshot: dict[str, Any] = {}
    for component in COMPONENTS:
        items = parse_list(
            run_kubectl(
                [
                    "--namespace",
                    DEVNET_NAMESPACE,
                    "get",
                    "pods",
                    "--selector",
                    f"app={component}",
                    "--output=json",
                ],
                context=context,
                error_message="pod health lookup failed",
            ),
            "pod health lookup",
        )
        if len(items) != replicas[component]:
            raise BaselineError("active pod count does not equal the Deployment replicas")
        pods: list[dict[str, Any]] = []
        for pod in items:
            metadata = require_mapping(pod, "metadata", "Pod metadata")
            spec = require_mapping(pod, "spec", "Pod spec")
            status = require_mapping(pod, "status", "Pod status")
            uid = metadata.get("uid")
            name = metadata.get("name")
            if (
                not isinstance(uid, str)
                or not uid
                or not isinstance(name, str)
                or not name
                or metadata.get("deletionTimestamp") is not None
                or spec.get("nodeName") != node_name
            ):
                raise BaselineError("active Pod identity is invalid")
            conditions = status.get("conditions")
            ready = isinstance(conditions, list) and any(
                isinstance(condition, dict)
                and condition.get("type") == "Ready"
                and condition.get("status") == "True"
                for condition in conditions
            )
            statuses = status.get("containerStatuses")
            if not isinstance(statuses, list):
                raise BaselineError("active Pod container status is invalid")
            component_statuses = [
                item
                for item in statuses
                if isinstance(item, dict) and item.get("name") == component
            ]
            if len(component_statuses) != 1:
                raise BaselineError("active Pod component status is invalid")
            component_status = component_statuses[0]
            restart_count = component_status.get("restartCount")
            if (
                not ready
                or component_status.get("ready") is not True
                or isinstance(restart_count, bool)
                or not isinstance(restart_count, int)
                or restart_count < 0
            ):
                raise BaselineError("active Pod is not ready and stable")
            pods.append(
                {
                    "name": name,
                    "uid": uid,
                    "restartCount": restart_count,
                    "ready": True,
                }
            )
        snapshot[component] = sorted(pods, key=lambda item: item["uid"])
    return snapshot


def fetch_endpoint_snapshot(
    context: str, replicas: dict[str, int], pods: dict[str, Any]
) -> dict[str, Any]:
    snapshot: dict[str, Any] = {}
    for component in COMPONENTS:
        items = parse_list(
            run_kubectl(
                [
                    "--namespace",
                    DEVNET_NAMESPACE,
                    "get",
                    "endpointslice",
                    "--selector",
                    f"kubernetes.io/service-name={component}",
                    "--output=json",
                ],
                context=context,
                error_message="endpoint health lookup failed",
            ),
            "endpoint health lookup",
        )
        endpoints: list[dict[str, Any]] = []
        pod_uids = {pod["uid"] for pod in pods[component]}
        for item in items:
            if item.get("kind") != "EndpointSlice":
                raise BaselineError("endpoint health lookup returned an invalid resource")
            if "endpoints" not in item:
                raise BaselineError("EndpointSlice endpoints is missing or invalid")
            slice_endpoints = item["endpoints"]
            if slice_endpoints is None:
                slice_endpoints = []
            elif not isinstance(slice_endpoints, list):
                raise BaselineError("EndpointSlice endpoints is missing or invalid")
            for endpoint in slice_endpoints:
                if not isinstance(endpoint, dict):
                    raise BaselineError("EndpointSlice endpoint is invalid")
                addresses = endpoint.get("addresses")
                conditions = endpoint.get("conditions", {})
                target_ref = endpoint.get("targetRef", {})
                if (
                    not isinstance(addresses, list)
                    or not all(isinstance(address, str) and address for address in addresses)
                    or not isinstance(conditions, dict)
                    or not isinstance(target_ref, dict)
                ):
                    raise BaselineError("EndpointSlice endpoint is invalid")
                target_uid = target_ref.get("uid")
                if not isinstance(target_uid, str) or target_uid not in pod_uids:
                    raise BaselineError("ready endpoint does not target an active Pod")
                endpoints.append(
                    {
                        "addresses": sorted(addresses),
                        "ready": conditions.get("ready"),
                        "serving": conditions.get("serving"),
                        "terminating": conditions.get("terminating"),
                        "targetUid": target_uid,
                    }
                )
        ready_count = sum(endpoint["ready"] is True for endpoint in endpoints)
        if ready_count != replicas[component]:
            raise BaselineError("ready endpoint count does not equal Deployment replicas")
        snapshot[component] = sorted(
            endpoints,
            key=lambda endpoint: json.dumps(endpoint, sort_keys=True, separators=(",", ":")),
        )
    return snapshot


def helm_revision(context: str) -> int:
    output = run_helm(
        [
            "list",
            "--kube-context",
            context,
            "--namespace",
            DEVNET_NAMESPACE,
            "--filter",
            f"^{DEVNET_RELEASE}$",
            "--output=json",
        ],
        error_message="Helm release metadata lookup failed",
    )
    try:
        releases = json.loads(output)
    except json.JSONDecodeError as error:
        raise BaselineError("Helm release metadata lookup returned invalid JSON") from error
    if not isinstance(releases, list) or len(releases) != 1:
        raise BaselineError("exact devnet Helm release was not found")
    release = releases[0]
    revision = release.get("revision") if isinstance(release, dict) else None
    status = release.get("status") if isinstance(release, dict) else None
    if isinstance(revision, str) and revision.isdigit():
        revision = int(revision)
    if (
        isinstance(revision, bool)
        or not isinstance(revision, int)
        or revision < 1
        or status != "deployed"
    ):
        raise BaselineError("devnet Helm release metadata is not deployable")
    return revision


def require_apply_permissions(
    context: str, resources: dict[tuple[str, str], dict[str, Any]]
) -> None:
    checks: list[tuple[str, str]] = [
        ("get", "secrets"),
        ("list", "secrets"),
        ("create", "secrets"),
        ("update", "secrets"),
    ]
    for kind, name in sorted(resources):
        checks.append(("patch", f"{kind.lower()}/{name}"))
    for verb, resource in checks:
        allowed = run_kubectl(
            [
                "auth",
                "can-i",
                verb,
                resource,
                "--namespace",
                DEVNET_NAMESPACE,
            ],
            context=context,
            error_message="Kubernetes authorization preflight failed",
        ).strip()
        if allowed != "yes":
            raise BaselineError("current identity lacks a required baseline permission")


def write_override_file(
    live: dict[str, Any],
    disable_oracle_keel_deployment_annotations: bool,
) -> str:
    components: dict[str, Any] = {}
    for component in COMPONENTS:
        components[component] = {
            "enabled": True,
            "image": live["images"][component]["repository"],
            "imageDigest": live["images"][component]["digest"],
            "replicas": live["replicas"][component],
            "ccInitData": live["policies"][component],
            "resources": live["resources"][component],
        }
    candle_collection = live["candleCollection"]
    components["oracle"]["candleCollection"] = {
        "enabled": candle_collection is not None,
        "value": candle_collection if candle_collection is not None else "",
    }
    environment_secret = live["environmentSecret"]
    components["oracle"]["environmentSecret"] = {
        "enabled": environment_secret is not None,
        "name": environment_secret[0] if environment_secret is not None else "",
        "optionalSet": (
            environment_secret is not None and environment_secret[1] is not None
        ),
        "optional": (
            environment_secret[1] is True if environment_secret is not None else False
        ),
    }
    oracle_keel_update_time = live["oracleKeelUpdateTime"]
    components["oracle"]["keelDeploymentAnnotationsEnabled"] = (
        not disable_oracle_keel_deployment_annotations
    )
    components["oracle"]["keelUpdateTime"] = {
        "enabled": oracle_keel_update_time is not None,
        "value": (
            oracle_keel_update_time if oracle_keel_update_time is not None else ""
        ),
    }
    sui_ref = live["suiRef"]
    override = {
        "namespace": DEVNET_NAMESPACE,
        "networkId": "devnet",
        "components": components,
        "payerSecretKey": live["payerKey"],
        "taskRunnerRpc": {
            "secretName": sui_ref[0] if sui_ref is not None else "",
            "suiMainnetRpcKey": sui_ref[1] if sui_ref is not None else "SUI_MAINNET_RPC",
        },
    }
    descriptor, path = tempfile.mkstemp(prefix=".helm-baseline-", suffix=".json")
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            descriptor = -1
            json.dump(override, stream, sort_keys=True, separators=(",", ":"))
            stream.write("\n")
    except BaseException:
        if descriptor >= 0:
            os.close(descriptor)
        Path(path).unlink(missing_ok=True)
        raise
    return path


def helm_upgrade_arguments(context: str, override_path: str) -> list[str]:
    return [
        "upgrade",
        DEVNET_RELEASE,
        str(CHART_DIR),
        "--kube-context",
        context,
        "--namespace",
        DEVNET_NAMESPACE,
        "--reuse-values",
        "--values",
        override_path,
        "--history-max",
        "0",
        "--no-hooks",
    ]


def extract_manifest(output: str) -> str:
    marker = "MANIFEST:\n"
    start = output.find(marker)
    if start < 0:
        raise BaselineError("Helm client dry-run did not return a manifest")
    manifest = output[start + len(marker) :]
    notes = manifest.find("\nNOTES:\n")
    if notes >= 0:
        manifest = manifest[:notes]
    validate_manifest_content(manifest, "Helm client dry-run")
    return manifest


def validate_manifest_content(manifest: str, label: str) -> None:
    if not manifest.strip():
        raise BaselineError(f"{label} returned an empty manifest")
    if SECRET_KIND_PATTERN.search(manifest) is not None:
        raise BaselineError(f"{label} unexpectedly contained a Secret")


def require_oracle_keel_opt_out_manifest_shape(manifest: str) -> None:
    oracle_documents = [
        document
        for document in re.split(r"(?m)^---[ \t]*$", manifest)
        if re.search(r"(?m)^kind:[ \t]*Deployment[ \t]*$", document)
        and re.search(r"(?m)^  name:[ \t]*oracle[ \t]*$", document)
    ]
    if len(oracle_documents) != 1:
        raise BaselineError(
            "Oracle Keel annotation opt-out manifest shape is invalid"
        )
    oracle_document = oracle_documents[0]
    if (
        len(
            re.findall(
                r"(?m)^  annotations:[ \t]*\{\}[ \t]*$",
                oracle_document,
            )
        )
        != 1
    ):
        raise BaselineError(
            "Oracle Keel annotation opt-out manifest must render an empty metadata map"
        )
    if any(key in oracle_document for key in ORACLE_KEEL_DEPLOYMENT_ANNOTATIONS):
        raise BaselineError(
            "Oracle Keel annotation opt-out manifest retained a protected annotation"
        )


def parse_protected_resources(
    output: str, label: str
) -> dict[tuple[str, str], dict[str, Any]]:
    resources: dict[tuple[str, str], dict[str, Any]] = {}
    for resource in parse_json_documents(output, label):
        kind = resource.get("kind")
        metadata = resource.get("metadata")
        name = metadata.get("name") if isinstance(metadata, dict) else None
        namespace = metadata.get("namespace") if isinstance(metadata, dict) else None
        if (
            kind not in ALLOWED_RENDERED_KINDS
            or name not in COMPONENTS
            or namespace != DEVNET_NAMESPACE
        ):
            raise BaselineError(f"{label} returned an unauthorized resource")
        key = (kind, name)
        if key in resources:
            raise BaselineError(f"{label} returned a duplicate resource")
        resources[key] = resource
    return resources


def parse_manifest_without_merge(
    context: str, manifest: str, label: str
) -> dict[tuple[str, str], dict[str, Any]]:
    output = run_kubectl(
        [
            "--namespace",
            DEVNET_NAMESPACE,
            "create",
            "--dry-run=client",
            "--filename=-",
            "--output=json",
        ],
        context=context,
        input_text=manifest,
        error_message=f"{label} parsing failed",
    )
    return parse_protected_resources(output, label)


def render_client_manifest(
    context: str, override_path: str
) -> tuple[str, dict[tuple[str, str], dict[str, Any]]]:
    helm_output = run_helm(
        [
            *helm_upgrade_arguments(context, override_path),
            "--dry-run=client",
            "--hide-secret",
        ],
        error_message="Helm client dry-run failed",
    )
    manifest = extract_manifest(helm_output)
    return manifest, parse_manifest_without_merge(
        context, manifest, "Helm client manifest"
    )


def fetch_stored_release_resources(
    context: str, revision: int
) -> dict[tuple[str, str], dict[str, Any]]:
    manifest = run_helm_protected_manifest(
        [
            "get",
            "manifest",
            DEVNET_RELEASE,
            "--kube-context",
            context,
            "--namespace",
            DEVNET_NAMESPACE,
            "--revision",
            str(revision),
        ]
    )
    validate_manifest_content(manifest, "stored Helm release manifest")
    return parse_manifest_without_merge(
        context,
        manifest,
        "stored Helm release manifest",
    )


def render_server_dry_run(
    context: str, manifest: str
) -> dict[tuple[str, str], dict[str, Any]]:
    server_output = run_kubectl(
        [
            "--namespace",
            DEVNET_NAMESPACE,
            "apply",
            "--dry-run=server",
            "--field-manager=switchboard-helm-baseline",
            "--filename=-",
            "--output=json",
        ],
        context=context,
        input_text=manifest,
        error_message="Kubernetes server dry-run failed",
    )
    return parse_protected_resources(server_output, "Kubernetes server dry-run")


def cpu_millicores(value: Any) -> Decimal | None:
    if not isinstance(value, str):
        return None
    match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)(m?)", value)
    if match is None:
        return None
    try:
        quantity = Decimal(match.group(1))
    except InvalidOperation:
        return None
    return quantity if match.group(2) == "m" else quantity * 1000


def scalar_semantically_equal(path: tuple[str, ...], live: Any, candidate: Any) -> bool:
    if live == candidate and type(live) is type(candidate):
        return True
    if path and path[-1] == "cpu" and "resources" in path:
        live_cpu = cpu_millicores(live)
        candidate_cpu = cpu_millicores(candidate)
        return live_cpu is not None and live_cpu == candidate_cpu
    return False


def named_list(value: list[Any]) -> dict[str, dict[str, Any]] | None:
    if not value or not all(isinstance(item, dict) for item in value):
        return None
    names = [item.get("name") for item in value]
    if not all(isinstance(name, str) and name for name in names):
        return None
    if len(set(names)) != len(names):
        raise BaselineError("protected resource contains a duplicate named list entry")
    return {item["name"]: item for item in value}


def require_candidate_subset(
    live: Any,
    candidate: Any,
    *,
    path: tuple[str, ...] = (),
    error_message: str,
) -> Any:
    if isinstance(candidate, dict):
        if not isinstance(live, dict):
            raise BaselineError(error_message)
        projected: dict[str, Any] = {}
        for key, child in candidate.items():
            if key not in live:
                raise BaselineError(error_message)
            projected[key] = require_candidate_subset(
                live[key],
                child,
                path=(*path, key),
                error_message=error_message,
            )
        return projected
    if isinstance(candidate, list):
        if not isinstance(live, list):
            raise BaselineError(error_message)
        candidate_named = named_list(candidate)
        live_named = named_list(live)
        if candidate_named is not None:
            if live_named is None:
                raise BaselineError(error_message)
            projected_list: list[Any] = []
            for item in candidate:
                name = item["name"]
                if name not in live_named:
                    raise BaselineError(error_message)
                projected_list.append(
                    require_candidate_subset(
                        live_named[name],
                        item,
                        path=(*path, name),
                        error_message=error_message,
                    )
                )
            return projected_list
        if len(live) != len(candidate):
            raise BaselineError(error_message)
        return [
            require_candidate_subset(
                live_item,
                candidate_item,
                path=(*path, str(index)),
                error_message=error_message,
            )
            for index, (live_item, candidate_item) in enumerate(
                zip(live, candidate)
            )
        ]
    if not scalar_semantically_equal(path, live, candidate):
        raise BaselineError(error_message)
    return candidate


def equivalence_proof(
    live: dict[tuple[str, str], dict[str, Any]],
    stored: dict[tuple[str, str], dict[str, Any]],
    rendered: dict[tuple[str, str], dict[str, Any]],
    candidate_label: str,
) -> dict[str, str]:
    if set(live) != set(rendered):
        raise BaselineError(f"{candidate_label} resource set differs from live")

    if pod_template_annotations(live) != pod_template_annotations(rendered):
        raise BaselineError(
            f"{candidate_label} would change Deployment template annotations"
        )

    live_specs = resource_specs(live)
    rendered_specs = resource_specs(rendered)
    require_candidate_subset(
        live_specs,
        rendered_specs,
        error_message=f"{candidate_label} would change a protected resource spec",
    )

    require_change_cause_live_only_contract(
        live,
        stored,
        rendered,
        candidate_label,
    )
    metadata_proof = metadata_three_way_preservation_proof(
        live,
        stored,
        rendered,
        candidate_label,
    )

    live_templates = pod_templates(live)
    rendered_templates = pod_templates(rendered)
    require_candidate_subset(
        live_templates,
        rendered_templates,
        error_message=f"{candidate_label} would change an active pod template",
    )

    live_environment_orders = environment_order_contract(live)
    rendered_environment_orders = environment_order_contract(rendered)
    if live_environment_orders != rendered_environment_orders:
        raise BaselineError(
            f"{candidate_label} would reorder a protected container environment"
        )

    live_replicas = replicas_map(live)
    rendered_replicas = replicas_map(rendered)
    if live_replicas != rendered_replicas:
        raise BaselineError(f"{candidate_label} would change a replica count")

    normalized_rendered_specs = resource_specs(normalize_environment_lists(rendered))
    rendered_secret_refs = collect_secret_references(normalized_rendered_specs)
    rendered_services = {
        key: value
        for key, value in rendered_specs.items()
        if key.startswith("Service/")
    }
    rendered_ingresses = {
        key: value
        for key, value in rendered_specs.items()
        if key.startswith("Ingress/")
    }

    return {
        "resourceSpecs": canonical_hash(rendered_specs),
        "resourceMetadata": metadata_proof,
        "podTemplates": canonical_hash(rendered_templates),
        "services": canonical_hash(rendered_services),
        "ingresses": canonical_hash(rendered_ingresses),
        "secretReferences": canonical_hash(rendered_secret_refs),
        "replicas": canonical_hash(rendered_replicas),
        "environmentOrders": canonical_hash(rendered_environment_orders),
    }


def environment_order_contract(
    resources: dict[tuple[str, str], dict[str, Any]],
) -> dict[str, list[str]]:
    contract: dict[str, list[str]] = {}
    for component in COMPONENTS:
        container = component_container(resources[("Deployment", component)], component)
        environment = require_list(
            container, "env", "Deployment container environment"
        )
        names: list[str] = []
        for item in environment:
            if not isinstance(item, dict):
                raise BaselineError("Deployment environment entry is invalid")
            name = item.get("name")
            if not isinstance(name, str) or not name or name in names:
                raise BaselineError("Deployment environment name is invalid")
            names.append(name)
        contract[component] = names
    return contract


def normalize_environment_lists(
    resources: dict[tuple[str, str], dict[str, Any]]
) -> dict[tuple[str, str], dict[str, Any]]:
    normalized = copy.deepcopy(resources)
    for component in COMPONENTS:
        deployment = normalized[("Deployment", component)]
        deployment_spec = require_mapping(deployment, "spec", "Deployment spec")
        template = require_mapping(
            deployment_spec, "template", "Deployment template"
        )
        pod_spec = require_mapping(template, "spec", "Deployment pod spec")
        for containers_key in ("containers", "initContainers"):
            if containers_key not in pod_spec:
                continue
            containers = require_list(
                pod_spec, containers_key, f"Deployment {containers_key}"
            )
            for container in containers:
                if not isinstance(container, dict):
                    raise BaselineError("Deployment container is invalid")
                if "env" not in container:
                    continue
                environment = require_list(
                    container, "env", "Deployment container environment"
                )
                keyed_environment: dict[str, dict[str, Any]] = {}
                for item in environment:
                    if not isinstance(item, dict):
                        raise BaselineError("Deployment environment entry is invalid")
                    name = item.get("name")
                    if not isinstance(name, str) or not name:
                        raise BaselineError("Deployment environment name is invalid")
                    if name in keyed_environment:
                        raise BaselineError(
                            "Deployment environment contains a duplicate name"
                        )
                    literal = item.get("value")
                    if isinstance(literal, str) and "$(" in literal:
                        raise BaselineError(
                            "Deployment environment contains an order-sensitive literal"
                        )
                    keyed_environment[name] = item
                container["env"] = keyed_environment
    return normalized


def remove_allowed_server_labels(
    live: dict[tuple[str, str], dict[str, Any]],
    client: dict[tuple[str, str], dict[str, Any]],
    server: dict[tuple[str, str], dict[str, Any]],
) -> dict[tuple[str, str], dict[str, Any]]:
    normalized = copy.deepcopy(server)
    for component in COMPONENTS:
        key = ("Deployment", component)
        live_metadata = require_mapping(live[key], "metadata", "resource metadata")
        client_metadata = require_mapping(
            client[key], "metadata", "resource metadata"
        )
        server_metadata = require_mapping(
            normalized[key], "metadata", "resource metadata"
        )
        live_labels = live_metadata.get("labels", {})
        client_labels = client_metadata.get("labels", {})
        server_labels = server_metadata.get("labels", {})
        if not all(
            isinstance(labels, dict)
            for labels in (live_labels, client_labels, server_labels)
        ):
            raise BaselineError("protected resource metadata is invalid")
        server_spec = require_mapping(
            normalized[key], "spec", "Deployment spec"
        )
        server_template = require_mapping(
            server_spec, "template", "Deployment template"
        )
        server_template_metadata = require_mapping(
            server_template, "metadata", "Deployment template metadata"
        )
        server_template_labels = require_mapping(
            server_template_metadata, "labels", "Deployment template labels"
        )
        for label_name in ("app", "chain"):
            if label_name in live_labels or label_name in client_labels:
                continue
            if label_name not in server_labels:
                continue
            label_value = server_labels[label_name]
            if (
                not isinstance(label_value, str)
                or server_template_labels.get(label_name) != label_value
            ):
                raise BaselineError(
                    "Kubernetes server dry-run added an invalid Deployment label"
                )
            del server_labels[label_name]
    return normalized


def require_server_metadata_equivalence(
    live: dict[tuple[str, str], dict[str, Any]],
    stored: dict[tuple[str, str], dict[str, Any]],
    client: dict[tuple[str, str], dict[str, Any]],
    server: dict[tuple[str, str], dict[str, Any]],
) -> None:
    live_contract = resource_metadata_contract(live)
    stored_contract = resource_metadata_contract(stored)
    client_contract = resource_metadata_contract(client)
    server_contract = resource_metadata_contract(server)
    error_message = (
        "Kubernetes server dry-run would change protected resource metadata"
    )
    require_candidate_subset(
        server_contract,
        client_contract,
        error_message=error_message,
    )

    for kind, name in sorted(server):
        identity = f"{kind}/{name}"
        for section in ("labels", "annotations"):
            live_values = live_contract[identity][section]
            stored_values = stored_contract[identity][section]
            client_values = client_contract[identity][section]
            server_values = server_contract[identity][section]
            for key in sorted(set(live_values) | set(server_values)):
                if key in client_values:
                    continue
                server_value = server_values.get(key, _MISSING_METADATA_VALUE)
                live_value = live_values.get(key, _MISSING_METADATA_VALUE)
                if (
                    key in stored_values
                    or server_value is _MISSING_METADATA_VALUE
                    or not metadata_value_equal(live_value, server_value)
                    or not allowed_live_only_metadata(
                        kind, section, key, server_value
                    )
                ):
                    raise BaselineError(error_message)

    metadata_three_way_preservation_proof(
        live,
        stored,
        server,
        "Kubernetes server dry-run",
    )


def require_server_semantic_equivalence(
    live: dict[tuple[str, str], dict[str, Any]],
    stored: dict[tuple[str, str], dict[str, Any]],
    client: dict[tuple[str, str], dict[str, Any]],
    server: dict[tuple[str, str], dict[str, Any]],
) -> None:
    if set(live) != set(client) or set(live) != set(server):
        raise BaselineError("Kubernetes server dry-run resource set differs from live")
    normalized_live = normalize_environment_lists(live)
    server_without_admission_labels = remove_allowed_server_labels(
        live, client, server
    )
    normalized_server = normalize_environment_lists(server_without_admission_labels)
    if resource_specs(normalized_live) != resource_specs(normalized_server):
        raise BaselineError(
            "Kubernetes server dry-run would change a protected resource spec"
        )
    require_server_metadata_equivalence(
        live,
        stored,
        client,
        server_without_admission_labels,
    )


def manifest_replica_scalar(deployment: dict[str, Any]) -> int:
    spec = require_mapping(deployment, "spec", "stored Deployment spec")
    replicas = spec.get("replicas")
    if isinstance(replicas, bool) or not isinstance(replicas, int) or replicas < 0:
        raise BaselineError("stored Helm manifest replica value is unsafe")
    return replicas


def prove_stored_manifest_transition(
    stored: dict[tuple[str, str], dict[str, Any]],
    candidate: dict[tuple[str, str], dict[str, Any]],
    disable_oracle_keel_deployment_annotations: bool,
) -> str:
    if set(stored) != set(candidate):
        raise BaselineError(
            "stored Helm manifest resource identities differ from the candidate"
        )

    normalized_stored = normalize_environment_lists(stored)
    normalized_candidate = normalize_environment_lists(candidate)
    allowed_paths: list[str] = []
    for component in COMPONENTS:
        key = ("Deployment", component)
        stored_deployment = normalized_stored[key]
        candidate_deployment = normalized_candidate[key]
        stored_spec = require_mapping(
            stored_deployment, "spec", "stored Deployment spec"
        )
        stored_replicas = manifest_replica_scalar(stored_deployment)
        candidate_replicas = manifest_replica_scalar(candidate_deployment)
        if stored_replicas != candidate_replicas:
            allowed_paths.append(f"Deployment/{component}/spec/replicas")
        stored_spec["replicas"] = candidate_replicas

        stored_container = component_container(stored_deployment, component)
        candidate_container = component_container(candidate_deployment, component)
        stored_image = stored_container.get("image")
        candidate_image = candidate_container.get("image")
        if not isinstance(stored_image, str) or not stored_image:
            raise BaselineError("stored Helm manifest image value is unsafe")
        parse_immutable_image(component, candidate_image)
        if stored_image != candidate_image:
            allowed_paths.append(
                f"Deployment/{component}/spec/template/spec/containers/{component}/image"
            )
        stored_container["image"] = candidate_image

        stored_requirements = require_mapping(
            stored_container, "resources", "stored resource requirements"
        )
        candidate_requirements = require_mapping(
            candidate_container, "resources", "candidate resource requirements"
        )
        for requirement_kind in ("limits", "requests"):
            stored_values = require_mapping(
                stored_requirements,
                requirement_kind,
                "stored resource requirements",
            )
            candidate_values = require_mapping(
                candidate_requirements,
                requirement_kind,
                "candidate resource requirements",
            )
            stored_cpu = stored_values.get("cpu")
            candidate_cpu = candidate_values.get("cpu")
            if stored_cpu != candidate_cpu:
                if (
                    cpu_millicores(stored_cpu) is None
                    or cpu_millicores(stored_cpu) != cpu_millicores(candidate_cpu)
                ):
                    raise BaselineError(
                        "stored Helm manifest contains an unsupported old-to-new change"
                    )
                allowed_paths.append(
                    "Deployment/"
                    f"{component}/spec/template/spec/containers/{component}/"
                    f"resources/{requirement_kind}/cpu"
                )
                stored_values["cpu"] = candidate_cpu

        stored_metadata = require_mapping(
            stored_deployment, "metadata", "stored Deployment metadata"
        )
        candidate_metadata = require_mapping(
            candidate_deployment, "metadata", "candidate Deployment metadata"
        )
        if component == "oracle" and disable_oracle_keel_deployment_annotations:
            stored_annotations = require_mapping(
                stored_metadata,
                "annotations",
                "stored Oracle Deployment annotations",
            )
            candidate_annotations = candidate_metadata.get("annotations", {})
            if not isinstance(candidate_annotations, dict):
                raise BaselineError(
                    "candidate Oracle Deployment annotations are invalid"
                )
            for annotation, expected_value in (
                ORACLE_KEEL_DEPLOYMENT_ANNOTATIONS.items()
            ):
                if (
                    stored_annotations.get(annotation) != expected_value
                    or annotation in candidate_annotations
                ):
                    raise BaselineError(
                        "stored Helm manifest contains an unsupported Oracle Keel annotation transition"
                    )
                del stored_annotations[annotation]
                allowed_paths.append(
                    "Deployment/oracle/metadata/annotations/"
                    + annotation.replace("/", "~1")
                )
            if not stored_annotations and "annotations" not in candidate_metadata:
                # kubectl may omit an empty annotations map from its JSON form. The
                # raw Helm manifest was separately required to contain
                # `annotations: {}`, so this is representation-only normalization.
                del stored_metadata["annotations"]
        stored_labels = require_mapping(
            stored_metadata, "labels", "stored Deployment labels"
        )
        candidate_labels = require_mapping(
            candidate_metadata, "labels", "candidate Deployment labels"
        )
        stored_cluster = stored_labels.get("cluster")
        candidate_cluster = candidate_labels.get("cluster")
        if stored_cluster != candidate_cluster:
            if stored_cluster not in (None, "") or candidate_cluster != "devnet":
                raise BaselineError(
                    "stored Helm manifest contains an unsupported old-to-new change"
                )
            allowed_paths.append(f"Deployment/{component}/metadata/labels/cluster")
            stored_labels["cluster"] = candidate_cluster

        if component == "oracle":
            stored_template = require_mapping(
                stored_spec, "template", "stored Deployment template"
            )
            candidate_spec = require_mapping(
                candidate_deployment, "spec", "candidate Deployment spec"
            )
            candidate_template = require_mapping(
                candidate_spec, "template", "candidate Deployment template"
            )
            stored_template_metadata = require_mapping(
                stored_template,
                "metadata",
                "stored Deployment template metadata",
            )
            candidate_template_metadata = require_mapping(
                candidate_template,
                "metadata",
                "candidate Deployment template metadata",
            )
            stored_template_annotations = require_mapping(
                stored_template_metadata,
                "annotations",
                "stored Deployment template annotations",
            )
            candidate_template_annotations = require_mapping(
                candidate_template_metadata,
                "annotations",
                "candidate Deployment template annotations",
            )
            stored_update_time = stored_template_annotations.get(
                KEEL_UPDATE_TIME_ANNOTATION,
                _MISSING_METADATA_VALUE,
            )
            candidate_update_time = candidate_template_annotations.get(
                KEEL_UPDATE_TIME_ANNOTATION,
                _MISSING_METADATA_VALUE,
            )
            if (
                stored_update_time is _MISSING_METADATA_VALUE
                and isinstance(candidate_update_time, str)
            ):
                allowed_paths.append(
                    "Deployment/oracle/spec/template/metadata/annotations/"
                    "keel.sh~1update-time"
                )
                stored_template_annotations[KEEL_UPDATE_TIME_ANNOTATION] = (
                    candidate_update_time
                )

            stored_environment = require_mapping(
                stored_container, "env", "stored Oracle environment"
            )
            candidate_environment = require_mapping(
                candidate_container, "env", "candidate Oracle environment"
            )
            if (
                "SUI_MAINNET_RPC" not in stored_environment
                and "SUI_MAINNET_RPC" in candidate_environment
            ):
                secret_reference(
                    candidate_environment["SUI_MAINNET_RPC"], "SUI_MAINNET_RPC"
                )
                allowed_paths.append(
                    "Deployment/oracle/spec/template/spec/containers/oracle/"
                    "env/SUI_MAINNET_RPC"
                )
                stored_environment["SUI_MAINNET_RPC"] = copy.deepcopy(
                    candidate_environment["SUI_MAINNET_RPC"]
                )

            stored_environment_secret = optional_environment_secret(stored_container)
            candidate_environment_secret = optional_environment_secret(
                candidate_container
            )
            if (
                stored_environment_secret is not None
                and candidate_environment_secret is not None
                and stored_environment_secret[0] == candidate_environment_secret[0]
                and stored_environment_secret[1] in (None, False)
                and candidate_environment_secret[1] is True
            ):
                stored_sources = require_list(
                    stored_container,
                    "envFrom",
                    "stored Oracle environment sources",
                )
                stored_secret_ref = require_mapping(
                    stored_sources[0],
                    "secretRef",
                    "stored Oracle environment Secret reference",
                )
                stored_secret_ref["optional"] = True
                allowed_paths.append(
                    "Deployment/oracle/spec/template/spec/containers/oracle/"
                    "envFrom/0/secretRef/optional"
                )

    if normalized_stored != normalized_candidate:
        raise BaselineError(
            "stored Helm manifest contains an unsupported old-to-new change"
        )
    return canonical_hash(
        {
            "protectedResources": [
                f"{kind}/{name}" for kind, name in sorted(candidate)
            ],
            "allowedScalarPaths": sorted(allowed_paths),
            "candidate": [
                {
                    "identity": f"{kind}/{name}",
                    "resource": normalized_candidate[(kind, name)],
                }
                for kind, name in sorted(normalized_candidate)
            ],
        }
    )


def race_guard(
    resources: dict[tuple[str, str], dict[str, Any]],
    pods: dict[str, Any],
    endpoints: dict[str, Any],
) -> str:
    return canonical_hash(
        {
            "resourceVersions": resource_version_guard(resources),
            "generations": deployment_generation_guard(resources),
            "specs": resource_specs(resources),
            "metadata": nonvolatile_resource_metadata(resources),
            "pods": pods,
            "endpoints": endpoints,
        }
    )


def print_proof(proof: dict[str, str]) -> None:
    for label in (
        "resourceSpecs",
        "resourceMetadata",
        "podTemplates",
        "services",
        "ingresses",
        "secretReferences",
        "replicas",
        "environmentOrders",
    ):
        print(f"{label}Equivalent=true hash={proof[label]}")


def main() -> int:
    args = parse_args()
    override_path: str | None = None
    operation_lock: int | None = None
    helm_invocation_started = False
    try:
        node_name = validate_target(
            args.network,
            args.host_id,
            args.disable_oracle_keel_deployment_annotations,
        )
        operation_lock = acquire_operation_lock()
        validate_tool_capabilities()
        context = run_kubectl(
            ["config", "current-context"],
            error_message="kubectl current-context lookup failed",
        ).strip()
        if not context:
            raise BaselineError("kubectl current context is empty")
        validate_cluster_identity(context, node_name)

        resources_before = fetch_resources(context)
        live = validate_live_resources(
            resources_before,
            args.expected_current_oracle_image,
            args.disable_oracle_keel_deployment_annotations,
        )
        pods_before = fetch_pod_snapshot(context, node_name, live["replicas"])
        endpoints_before = fetch_endpoint_snapshot(
            context, live["replicas"], pods_before
        )
        revision_before = helm_revision(context)
        guard_before = race_guard(resources_before, pods_before, endpoints_before)

        override_path = write_override_file(
            live,
            args.disable_oracle_keel_deployment_annotations,
        )
        manifest, client_resources = render_client_manifest(context, override_path)
        if args.disable_oracle_keel_deployment_annotations:
            require_oracle_keel_opt_out_manifest_shape(manifest)
        stored_resources = fetch_stored_release_resources(context, revision_before)
        proof = equivalence_proof(
            resources_before,
            stored_resources,
            client_resources,
            "Helm client manifest",
        )
        stored_transition_hash = prove_stored_manifest_transition(
            stored_resources,
            client_resources,
            args.disable_oracle_keel_deployment_annotations,
        )
        server_resources = render_server_dry_run(context, manifest)
        require_server_semantic_equivalence(
            resources_before,
            stored_resources,
            client_resources,
            server_resources,
        )
        print(
            f"target=devnet/{args.host_id} namespace={DEVNET_NAMESPACE} "
            f"release={DEVNET_RELEASE}"
        )
        print("coordinatorExclusiveWindowAsserted=true")
        print("hostLocalOperationLockHeld=true")
        print_proof(proof)
        if args.disable_oracle_keel_deployment_annotations:
            print(
                "oracleKeelStoredDeletionRestricted=true "
                f"hash={stored_transition_hash}"
            )
        else:
            print(f"helmPatchDeletionFree=true hash={stored_transition_hash}")
        print(f"activePodsStable=true hash={canonical_hash(pods_before)}")
        print(f"endpointsStable=true hash={canonical_hash(endpoints_before)}")

        if not args.apply:
            print(f"currentHelmRevision={revision_before}")
            print("action=planned")
            return 0

        resources_guarded = fetch_resources(context)
        protected_versions_before_helm = resource_version_guard(resources_guarded)
        nonvolatile_metadata_before_helm = nonvolatile_resource_metadata(
            resources_guarded,
            ignore_oracle_deployment_generation=(
                args.disable_oracle_keel_deployment_annotations
            ),
        )
        generations_before_helm = deployment_generation_guard(resources_guarded)
        guarded_live = validate_live_resources(
            resources_guarded,
            args.expected_current_oracle_image,
            args.disable_oracle_keel_deployment_annotations,
        )
        pods_guarded = fetch_pod_snapshot(
            context, node_name, guarded_live["replicas"]
        )
        endpoints_guarded = fetch_endpoint_snapshot(
            context, guarded_live["replicas"], pods_guarded
        )
        if race_guard(resources_guarded, pods_guarded, endpoints_guarded) != guard_before:
            raise BaselineError("live state drifted after dry-run; Helm was not invoked")
        if helm_revision(context) != revision_before:
            raise BaselineError("Helm revision drifted after dry-run; Helm was not invoked")

        require_apply_permissions(context, resources_guarded)

        helm_invocation_started = True
        run_helm(
            helm_upgrade_arguments(context, override_path),
            error_message="Helm baseline upgrade failed",
        )
        revision_after = helm_revision(context)
        if revision_after != revision_before + 1:
            raise BaselineError("Helm baseline revision was not recorded exactly once")

        resources_after = fetch_resources(context)
        protected_versions_after = resource_version_guard(resources_after)
        if args.disable_oracle_keel_deployment_annotations:
            for identity, resource_version in protected_versions_before_helm.items():
                if (
                    identity != "Deployment/oracle"
                    and protected_versions_after.get(identity) != resource_version
                ):
                    raise BaselineError(
                        "non-Oracle resourceVersion changed during Keel opt-out baseline creation"
                    )
        elif protected_versions_after != protected_versions_before_helm:
            raise BaselineError(
                "protected resourceVersion changed during baseline creation"
            )
        generations_after = deployment_generation_guard(resources_after)
        if args.disable_oracle_keel_deployment_annotations:
            if generations_after["oracle"] < generations_before_helm["oracle"]:
                raise BaselineError(
                    "Oracle Deployment generation decreased during Keel opt-out baseline creation"
                )
            for component in ("guardian", "gateway"):
                if generations_after[component] != generations_before_helm[component]:
                    raise BaselineError(
                        "non-Oracle Deployment generation changed during Keel opt-out baseline creation"
                    )
        elif generations_after != generations_before_helm:
            raise BaselineError(
                "Deployment generation changed during baseline creation"
            )
        if nonvolatile_resource_metadata(
            resources_after,
            ignore_oracle_deployment_generation=(
                args.disable_oracle_keel_deployment_annotations
            ),
        ) != nonvolatile_metadata_before_helm:
            raise BaselineError(
                "protected resource metadata changed during baseline creation"
            )
        after_live = validate_live_resources(
            resources_after,
            args.expected_current_oracle_image,
            args.disable_oracle_keel_deployment_annotations,
        )
        if resource_specs(resources_after) != resource_specs(resources_guarded):
            raise BaselineError("protected resource spec changed during baseline creation")
        if collect_secret_references(resource_specs(resources_after)) != collect_secret_references(
            resource_specs(resources_guarded)
        ):
            raise BaselineError("Secret reference changed during baseline creation")
        if after_live["replicas"] != live["replicas"]:
            raise BaselineError("replica count changed during baseline creation")

        pods_after = fetch_pod_snapshot(context, node_name, live["replicas"])
        endpoints_after = fetch_endpoint_snapshot(
            context, live["replicas"], pods_after
        )
        if pods_after != pods_guarded:
            raise BaselineError("active pod identity or health changed during baseline creation")
        if endpoints_after != endpoints_guarded:
            raise BaselineError("service endpoints changed during baseline creation")

        print(f"baselineHelmRevision={revision_after}")
        print(f"rollbackRevision={revision_after}")
        print("postApplyResourceSpecsUnchanged=true")
        if args.disable_oracle_keel_deployment_annotations:
            oracle_resource_version_changed = (
                protected_versions_after["Deployment/oracle"]
                != protected_versions_before_helm["Deployment/oracle"]
            )
            print(
                "postApplyOracleResourceVersionChanged="
                f"{str(oracle_resource_version_changed).lower()}"
            )
            print("postApplyOtherResourceVersionsUnchanged=true")
            oracle_generation_advanced = (
                generations_after["oracle"] > generations_before_helm["oracle"]
            )
            print(
                "postApplyOracleGenerationAdvanced="
                f"{str(oracle_generation_advanced).lower()}"
            )
            print("postApplyOtherDeploymentGenerationsUnchanged=true")
            print("postApplyOracleMetadataOnlyRecord=true")
        else:
            print("postApplyResourceVersionsUnchanged=true")
            print("postApplyDeploymentGenerationsUnchanged=true")
        print("postApplyNonvolatileMetadataUnchanged=true")
        print("postApplyPodUidsRestartsReadinessUnchanged=true")
        print("postApplyEndpointsUnchanged=true")
        print("action=baseline-recorded")
        return 0
    except BaselineError as error:
        if helm_invocation_started:
            print(
                "mutationState=requires-secret-safe-Helm-revision-readback",
                file=sys.stderr,
            )
        print(f"error: {error}", file=sys.stderr)
        return 1
    finally:
        if override_path is not None:
            Path(override_path).unlink(missing_ok=True)
        if operation_lock is not None:
            release_operation_lock(operation_lock)


if __name__ == "__main__":
    raise SystemExit(main())
