#!/usr/bin/env python3
"""Reconcile one explicitly selected devnet auxiliary Deployment.

This entrypoint intentionally cannot render or apply the shared Helm release.
It validates an existing Guardian or Gateway Deployment, then atomically
changes only that Deployment's container image. The checked-in replica count
is a precondition, never a scaling instruction.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
DESIRED_STATE_ROOT = SCRIPT_DIR / "desired-state" / "devnet"
DEVNET_NAMESPACE = "switchboard-oracle-devnet"
DIGEST_PATTERN = re.compile(r"sha256:[a-f0-9]{64}")
IMAGE_TAG_PATTERN = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}")
HOST_ID_PATTERN = re.compile(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?")
COMPONENT_IMAGES = {
    "guardian": "docker.io/switchboardlabs/guardian",
    "gateway": "docker.io/switchboardlabs/gateway",
}
AUTHORIZED_TARGETS = {
    "stra01": {
        "component": "guardian",
        "nodeName": "ovh-stra-01",
        "replicas": 0,
    },
    "lim05": {
        "component": "gateway",
        "nodeName": "ovh-lim-05",
        "replicas": 1,
    },
}
DESIRED_KEYS = {
    "applyEnabled",
    "component",
    "hostId",
    "image",
    "imageDigest",
    "network",
    "namespace",
    "nodeName",
    "replicas",
}


class ReconcileError(Exception):
    """A fail-closed desired-state or live-state validation error."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate or apply one devnet auxiliary desired-state overlay."
    )
    parser.add_argument("--network", required=True)
    parser.add_argument("--host-id", required=True)
    parser.add_argument(
        "--expected-current-image",
        help="Exact image reference from the preceding read-only plan; required before mutation.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Apply the image-only JSON patch after all preconditions pass.",
    )
    return parser.parse_args()


def strict_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ReconcileError(f"duplicate desired-state key: {key}")
        result[key] = value
    return result


def load_desired_state(network: str, host_id: str) -> dict[str, Any]:
    if network != "devnet":
        raise ReconcileError("auxiliary desired-state reconciliation is devnet-only")
    if HOST_ID_PATTERN.fullmatch(host_id) is None:
        raise ReconcileError("host ID is invalid")
    if host_id not in AUTHORIZED_TARGETS:
        raise ReconcileError(f"unknown devnet host ID: {host_id}")

    overlay_path = DESIRED_STATE_ROOT / f"{host_id}.json"
    if not overlay_path.is_file():
        raise ReconcileError(f"desired-state overlay is missing for host ID: {host_id}")

    try:
        desired = json.loads(
            overlay_path.read_text(encoding="utf-8"),
            object_pairs_hook=strict_object,
        )
    except (OSError, json.JSONDecodeError) as error:
        raise ReconcileError("desired-state overlay is unreadable or invalid JSON") from error

    if not isinstance(desired, dict) or set(desired) != DESIRED_KEYS:
        raise ReconcileError("desired-state overlay has an invalid schema")
    if desired["network"] != network:
        raise ReconcileError("desired-state network does not match requested network")
    if desired["hostId"] != host_id:
        raise ReconcileError("desired-state host ID does not match requested host ID")
    if desired["namespace"] != DEVNET_NAMESPACE:
        raise ReconcileError("desired-state namespace is not the exact devnet namespace")
    if not isinstance(desired["nodeName"], str) or not desired["nodeName"]:
        raise ReconcileError("desired-state node name is invalid")
    if not isinstance(desired["applyEnabled"], bool):
        raise ReconcileError("desired-state apply gate is invalid")

    component = desired["component"]
    if not isinstance(component, str) or component not in COMPONENT_IMAGES:
        raise ReconcileError("desired-state component is not an auxiliary workload")
    if desired["image"] != COMPONENT_IMAGES[component]:
        raise ReconcileError("desired-state image repository is not authorized")
    if not isinstance(desired["imageDigest"], str) or DIGEST_PATTERN.fullmatch(
        desired["imageDigest"]
    ) is None:
        raise ReconcileError("desired-state image digest is not immutable")
    replicas = desired["replicas"]
    if isinstance(replicas, bool) or not isinstance(replicas, int) or replicas < 0:
        raise ReconcileError("desired-state replica count is invalid")
    target = AUTHORIZED_TARGETS[host_id]
    if any(desired[key] != value for key, value in target.items()):
        raise ReconcileError("desired-state target identity does not match the authorized host")
    return desired


def run_kubectl(arguments: list[str], *, context: str | None = None) -> str:
    command = ["kubectl"]
    if context is not None:
        command.extend(["--context", context])
    command.extend(arguments)
    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise ReconcileError("kubectl command failed")
    return result.stdout


def parse_deployment(output: str) -> dict[str, Any]:
    try:
        deployment = json.loads(output)
    except json.JSONDecodeError as error:
        raise ReconcileError("kubectl returned invalid Deployment JSON") from error
    if not isinstance(deployment, dict):
        raise ReconcileError("kubectl returned an invalid Deployment object")
    return deployment


def get_deployment(context: str, namespace: str, component: str) -> dict[str, Any]:
    output = run_kubectl(
        ["--namespace", namespace, "get", "deployment", component, "--output=json"],
        context=context,
    )
    return parse_deployment(output)


def validate_cluster_identity(context: str, desired: dict[str, Any]) -> None:
    output = run_kubectl(["get", "nodes", "--output=json"], context=context)
    try:
        node_list = json.loads(output)
    except json.JSONDecodeError as error:
        raise ReconcileError("kubectl returned invalid Node list JSON") from error
    if (
        not isinstance(node_list, dict)
        or node_list.get("apiVersion") != "v1"
        or node_list.get("kind") != "List"
    ):
        raise ReconcileError("kubectl returned an invalid Node list")
    items = node_list.get("items")
    if not isinstance(items, list) or len(items) != 1:
        raise ReconcileError("target context must contain exactly one Kubernetes node")
    node = items[0]
    if not isinstance(node, dict):
        raise ReconcileError("target context returned an invalid Kubernetes node")
    metadata = node.get("metadata")
    if not isinstance(metadata, dict) or metadata.get("name") != desired["nodeName"]:
        raise ReconcileError("target context node does not match desired-state host identity")


def require_mapping(parent: dict[str, Any], key: str) -> dict[str, Any]:
    value = parent.get(key)
    if not isinstance(value, dict):
        raise ReconcileError(f"Deployment field is missing or invalid: {key}")
    return value


def validate_live_deployment(
    deployment: dict[str, Any], desired: dict[str, Any], namespace: str
) -> dict[str, Any]:
    component = desired["component"]
    metadata = require_mapping(deployment, "metadata")
    spec = require_mapping(deployment, "spec")
    template = require_mapping(spec, "template")
    template_metadata = require_mapping(template, "metadata")
    template_spec = require_mapping(template, "spec")

    if deployment.get("apiVersion") != "apps/v1" or deployment.get("kind") != "Deployment":
        raise ReconcileError("live object is not an apps/v1 Deployment")
    if metadata.get("name") != component or metadata.get("namespace") != namespace:
        raise ReconcileError("live Deployment identity does not match the requested target")
    resource_version = metadata.get("resourceVersion")
    if not isinstance(resource_version, str) or not resource_version:
        raise ReconcileError("live Deployment resourceVersion is missing")

    labels = require_mapping(metadata, "labels")
    selector = require_mapping(require_mapping(spec, "selector"), "matchLabels")
    template_labels = require_mapping(template_metadata, "labels")
    if (
        labels.get("app") != component
        or selector.get("app") != component
        or template_labels.get("app") != component
    ):
        raise ReconcileError("live Deployment labels do not match the auxiliary target")

    live_replicas = spec.get("replicas")
    if (
        isinstance(live_replicas, bool)
        or not isinstance(live_replicas, int)
        or live_replicas != desired["replicas"]
    ):
        raise ReconcileError(
            "live replica count differs from desired state; refusing to scale implicitly"
        )

    containers = template_spec.get("containers")
    if not isinstance(containers, list):
        raise ReconcileError("live Deployment containers are missing")
    matching_containers = [
        (index, container)
        for index, container in enumerate(containers)
        if isinstance(container, dict) and container.get("name") == component
    ]
    if len(matching_containers) != 1:
        raise ReconcileError("live Deployment does not have exactly one target container")
    container_index, container = matching_containers[0]

    current_image = container.get("image")
    digest_prefix = f'{desired["image"]}@'
    tag_prefix = f'{desired["image"]}:'
    current_is_immutable = (
        isinstance(current_image, str)
        and current_image.startswith(digest_prefix)
        and DIGEST_PATTERN.fullmatch(current_image.removeprefix(digest_prefix)) is not None
    )
    current_is_authorized_tag = (
        isinstance(current_image, str)
        and current_image.startswith(tag_prefix)
        and IMAGE_TAG_PATTERN.fullmatch(current_image.removeprefix(tag_prefix)) is not None
    )
    if not current_is_immutable and not current_is_authorized_tag:
        raise ReconcileError(
            "live image does not use the authorized repository and a valid tag or digest"
        )
    env = container.get("env")
    if not isinstance(env, list):
        raise ReconcileError("live Deployment environment is missing")
    network_entries = [
        (index, item)
        for index, item in enumerate(env)
        if isinstance(item, dict) and item.get("name") == "NETWORK_ID"
    ]
    if len(network_entries) != 1:
        raise ReconcileError("live Deployment NETWORK_ID is missing or ambiguous")
    network_index, network_entry = network_entries[0]
    if network_entry.get("value") != desired["network"] or "valueFrom" in network_entry:
        raise ReconcileError("live Deployment network does not match desired state")

    return {
        "containerIndex": container_index,
        "currentImage": current_image,
        "currentImageIsImmutable": current_is_immutable,
        "networkIndex": network_index,
        "resourceVersion": resource_version,
    }


def build_patch(
    desired: dict[str, Any], namespace: str, live: dict[str, Any]
) -> list[dict[str, Any]]:
    component = desired["component"]
    container_index = live["containerIndex"]
    network_index = live["networkIndex"]
    expected_image = f'{desired["image"]}@{desired["imageDigest"]}'
    return [
        {"op": "test", "path": "/metadata/resourceVersion", "value": live["resourceVersion"]},
        {"op": "test", "path": "/metadata/name", "value": component},
        {"op": "test", "path": "/metadata/namespace", "value": namespace},
        {"op": "test", "path": "/metadata/labels/app", "value": component},
        {"op": "test", "path": "/spec/replicas", "value": desired["replicas"]},
        {"op": "test", "path": "/spec/selector/matchLabels/app", "value": component},
        {"op": "test", "path": "/spec/template/metadata/labels/app", "value": component},
        {
            "op": "test",
            "path": f"/spec/template/spec/containers/{container_index}/name",
            "value": component,
        },
        {
            "op": "test",
            "path": f"/spec/template/spec/containers/{container_index}/image",
            "value": live["currentImage"],
        },
        {
            "op": "test",
            "path": f"/spec/template/spec/containers/{container_index}/env/{network_index}/name",
            "value": "NETWORK_ID",
        },
        {
            "op": "test",
            "path": f"/spec/template/spec/containers/{container_index}/env/{network_index}/value",
            "value": desired["network"],
        },
        {
            "op": "replace",
            "path": f"/spec/template/spec/containers/{container_index}/image",
            "value": expected_image,
        },
    ]


def build_rollback_patch(
    desired: dict[str, Any], rollback_image: str, live: dict[str, Any]
) -> list[dict[str, Any]]:
    component = desired["component"]
    container_index = live["containerIndex"]
    desired_image = f'{desired["image"]}@{desired["imageDigest"]}'
    return [
        {"op": "test", "path": "/metadata/resourceVersion", "value": live["resourceVersion"]},
        {"op": "test", "path": "/metadata/name", "value": component},
        {"op": "test", "path": "/metadata/namespace", "value": desired["namespace"]},
        {"op": "test", "path": "/spec/replicas", "value": desired["replicas"]},
        {
            "op": "test",
            "path": f"/spec/template/spec/containers/{container_index}/name",
            "value": component,
        },
        {
            "op": "test",
            "path": f"/spec/template/spec/containers/{container_index}/image",
            "value": desired_image,
        },
        {
            "op": "replace",
            "path": f"/spec/template/spec/containers/{container_index}/image",
            "value": rollback_image,
        },
    ]


def patch_deployment(
    context: str,
    namespace: str,
    component: str,
    patch: list[dict[str, Any]],
) -> dict[str, Any]:
    output = run_kubectl(
        [
            "--namespace",
            namespace,
            "patch",
            "deployment",
            component,
            "--type=json",
            "--patch",
            json.dumps(patch, separators=(",", ":")),
            "--output=json",
        ],
        context=context,
    )
    return parse_deployment(output)


def recover_after_patch_failure(
    context: str,
    namespace: str,
    desired: dict[str, Any],
    rollback_image: str,
) -> str:
    component = desired["component"]
    deployment = get_deployment(context, namespace, component)
    live = validate_live_deployment(deployment, desired, namespace)
    desired_image = f'{desired["image"]}@{desired["imageDigest"]}'
    if live["currentImage"] == rollback_image:
        return "unchanged"
    if live["currentImage"] != desired_image:
        raise ReconcileError("live image is neither the desired nor rollback image")

    rollback_patch = build_rollback_patch(desired, rollback_image, live)
    rolled_back = patch_deployment(
        context,
        namespace,
        component,
        rollback_patch,
    )
    rolled_back_live = validate_live_deployment(rolled_back, desired, namespace)
    if rolled_back_live["currentImage"] != rollback_image:
        raise ReconcileError("rollback patch response did not restore the prior image")
    recovered = get_deployment(context, namespace, component)
    recovered_live = validate_live_deployment(recovered, desired, namespace)
    if recovered_live["currentImage"] != rollback_image:
        raise ReconcileError("rollback image was not confirmed by a fresh read")
    return "restored"


def main() -> int:
    args = parse_args()
    try:
        desired = load_desired_state(args.network, args.host_id)
        if shutil.which("kubectl") is None:
            raise ReconcileError("required command is unavailable: kubectl")

        context = run_kubectl(["config", "current-context"]).strip()
        if not context:
            raise ReconcileError("kubectl current context is empty")
        component = desired["component"]
        namespace = desired["namespace"]
        validate_cluster_identity(context, desired)
        deployment = get_deployment(context, namespace, component)
        live = validate_live_deployment(deployment, desired, namespace)
        desired_image = f'{desired["image"]}@{desired["imageDigest"]}'

        print(
            f'target={desired["network"]}/{desired["hostId"]} '
            f'node={desired["nodeName"]} namespace={namespace} component={component} '
            f'replicas={desired["replicas"]}'
        )
        print(f'currentImage={live["currentImage"]}')
        print(f"desiredImage={desired_image}")

        if live["currentImage"] == desired_image:
            print("action=noop")
            return 0
        if not args.apply:
            print("action=planned")
            return 0
        if not desired["applyEnabled"]:
            raise ReconcileError("apply is disabled for this desired-state target")
        if desired["replicas"] != 0 and not live["currentImageIsImmutable"]:
            raise ReconcileError(
                "a running auxiliary workload requires an immutable current rollback image"
            )
        if args.expected_current_image is None:
            raise ReconcileError(
                "--expected-current-image is required before applying a change"
            )
        if args.expected_current_image != live["currentImage"]:
            raise ReconcileError("live image differs from the operator-confirmed current image")

        can_patch = run_kubectl(
            [
                "auth",
                "can-i",
                "patch",
                f"deployment/{component}",
                "--namespace",
                namespace,
            ],
            context=context,
        ).strip()
        if can_patch != "yes":
            raise ReconcileError("current identity cannot patch the target Deployment")

        patch = build_patch(desired, namespace, live)
        try:
            patched = patch_deployment(context, namespace, component, patch)
            patched_live = validate_live_deployment(patched, desired, namespace)
            if patched_live["currentImage"] != desired_image:
                raise ReconcileError("patch response does not match desired state")
        except ReconcileError as forward_error:
            raise ReconcileError(
                f"forward image patch was not confirmed: {forward_error}; "
                "no automatic rollback was attempted; "
                f'operator recovery image is {live["currentImage"]}'
            ) from forward_error

        try:
            deployed = get_deployment(context, namespace, component)
            deployed_live = validate_live_deployment(deployed, desired, namespace)
            if deployed_live["currentImage"] != desired_image:
                raise ReconcileError("target image does not match desired state after patch")
        except ReconcileError as verification_error:
            try:
                recovery = recover_after_patch_failure(
                    context,
                    namespace,
                    desired,
                    live["currentImage"],
                )
            except ReconcileError as recovery_error:
                raise ReconcileError(
                    f"image patch verification failed: {verification_error}; "
                    f"recovery could not be proven: {recovery_error}; "
                    f'operator recovery image is {live["currentImage"]}'
                ) from recovery_error
            raise ReconcileError(
                f"image patch verification failed: {verification_error}; "
                f"recovery={recovery}; "
                f'operator recovery image is {live["currentImage"]}'
            ) from verification_error

        print("action=applied")
        return 0
    except ReconcileError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
