#!/usr/bin/env python3

from __future__ import annotations

import copy
import fcntl
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_DIR = Path(__file__).resolve().parents[3]
SCRIPT = REPO_DIR / ".scripts/kubernetes/k8s-oracle-helm-baseline.py"
NAMESPACE = "switchboard-oracle-devnet"
RELEASE = "sb-oracle-devnet"
CONTEXT = "test-context"
NODE_NAME = "ovh-stra-01"
RBX_NODE_NAME = "ovh-rbx-01"
COMPONENTS = ("oracle", "guardian", "gateway")
ORACLE_KEEL_DEPLOYMENT_ANNOTATIONS = {
    "keel.sh/approvals": "0",
    "keel.sh/trigger": "poll",
    "keel.sh/match-tag": "true",
    "keel.sh/policy": "force",
}
ORACLE_IMAGE = f"docker.io/switchboardlabs/oracle@sha256:{'a' * 64}"
GUARDIAN_IMAGE = f"docker.io/switchboardlabs/guardian@sha256:{'b' * 64}"
GATEWAY_IMAGE = f"docker.io/switchboardlabs/gateway@sha256:{'c' * 64}"
PAYER_KEY = "payer-key-must-not-appear"
SUI_NAME = "sui-name-must-not-appear"
SUI_KEY = "sui-key-must-not-appear"
POLICY_SENTINEL = "policy-must-not-appear"
CANDLE_SENTINEL = "candle-value-must-not-appear"
ENVIRONMENT_SECRET_SENTINEL = "environment-secret-must-not-appear"
KEEL_UPDATE_TIME_SENTINEL = "keel-update-time-must-not-appear"
LOCK_FILE = Path("/run/lock/switchboard-oracle-devnet-helm-baseline.lock")
PROTECTED_FILES = [
    REPO_DIR / ".scripts/helm/charts/on-demand/values.yaml",
    REPO_DIR / ".scripts/helm/charts/on-demand/templates/oracle.yaml",
    REPO_DIR / ".scripts/helm/charts/on-demand/templates/guardian.yaml",
    REPO_DIR / ".scripts/helm/charts/on-demand/templates/gateway.yaml",
    REPO_DIR / ".scripts/kubernetes/k8s-oracle-rollout.sh",
]


def file_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def owned_metadata(name: str, resource_version: str) -> dict[str, object]:
    return {
        "name": name,
        "namespace": NAMESPACE,
        "resourceVersion": resource_version,
        "labels": {"app": name, "app.kubernetes.io/managed-by": "Helm"},
        "annotations": {
            "meta.helm.sh/release-name": RELEASE,
            "meta.helm.sh/release-namespace": NAMESPACE,
        },
    }


def secret_env(name: str, secret_name: str, key: str) -> dict[str, object]:
    return {
        "name": name,
        "valueFrom": {"secretKeyRef": {"name": secret_name, "key": key}},
    }


def deployment(
    component: str,
    image: str,
    replicas: int,
    resource_version: str,
    *,
    policy: str | None = None,
) -> dict[str, object]:
    metadata = owned_metadata(component, resource_version)
    metadata["labels"].update({"chain": "solana", "cluster": "devnet"})
    metadata["generation"] = 1
    annotations: dict[str, str] = {
        "io.containerd.cri.runtime-handler": "kata-qemu-snp",
    }
    if policy is not None:
        annotations["io.katacontainers.config.runtime.cc_init_data"] = policy
    env: list[dict[str, object]] = [
        {"name": "NETWORK_ID", "value": "devnet"},
        {"name": "CHAIN", "value": "solana"},
        secret_env("PAYER_SECRET", "payer-secret", PAYER_KEY),
    ]
    if component == "oracle":
        env.append(secret_env("SUI_MAINNET_RPC", SUI_NAME, SUI_KEY))
        env.append({"name": "CANDLE_COLLECTION_ENABLED", "value": CANDLE_SENTINEL})
    return {
        "apiVersion": "apps/v1",
        "kind": "Deployment",
        "metadata": metadata,
        "spec": {
            "replicas": replicas,
            "selector": {"matchLabels": {"app": component}},
            "strategy": {
                "rollingUpdate": {"maxSurge": 1, "maxUnavailable": 0},
                "type": "RollingUpdate",
            },
            "template": {
                "metadata": {
                    "labels": {
                        "app": component,
                        "chain": "solana",
                        "cluster": "devnet",
                    },
                    "annotations": annotations,
                },
                "spec": {
                    "runtimeClassName": "kata-qemu-snp",
                    "dnsPolicy": "ClusterFirst",
                    "containers": [
                        {
                            "name": component,
                            "image": image,
                            "imagePullPolicy": "Always",
                            "env": env,
                            **(
                                {
                                    "envFrom": [
                                        {
                                            "secretRef": {
                                                "name": ENVIRONMENT_SECRET_SENTINEL
                                            }
                                        }
                                    ]
                                }
                                if component == "oracle"
                                else {}
                            ),
                            "resources": {
                                "limits": {"cpu": "4", "memory": "2000Mi"},
                                "requests": {"cpu": "100m", "memory": "100Mi"},
                            },
                        }
                    ],
                },
            },
        },
    }


def service(component: str, resource_version: str) -> dict[str, object]:
    return {
        "apiVersion": "v1",
        "kind": "Service",
        "metadata": owned_metadata(component, resource_version),
        "spec": {
            "clusterIP": f"10.0.0.{len(component)}",
            "ports": [{"port": 8080, "protocol": "TCP", "targetPort": 8080}],
            "selector": {"app": component},
            "type": "ClusterIP",
        },
    }


def ingress(component: str, resource_version: str) -> dict[str, object]:
    return {
        "apiVersion": "networking.k8s.io/v1",
        "kind": "Ingress",
        "metadata": owned_metadata(component, resource_version),
        "spec": {
            "ingressClassName": "nginx",
            "rules": [
                {
                    "host": "devnet.example.invalid",
                    "http": {
                        "paths": [
                            {
                                "path": f"/devnet/{component}",
                                "pathType": "Prefix",
                                "backend": {
                                    "service": {
                                        "name": component,
                                        "port": {"number": 8080},
                                    }
                                },
                            }
                        ]
                    },
                }
            ],
        },
    }


def resources(
    *,
    oracle_replicas: int = 1,
    guardian_image: str = GUARDIAN_IMAGE,
    policies: dict[str, str | None] | None = None,
) -> list[dict[str, object]]:
    policies = policies or {component: None for component in COMPONENTS}
    images = {
        "oracle": ORACLE_IMAGE,
        "guardian": guardian_image,
        "gateway": GATEWAY_IMAGE,
    }
    replicas = {"oracle": oracle_replicas, "guardian": 0, "gateway": 1}
    result: list[dict[str, object]] = []
    for index, component in enumerate(COMPONENTS, start=1):
        result.extend(
            [
                deployment(
                    component,
                    images[component],
                    replicas[component],
                    str(index),
                    policy=policies[component],
                ),
                service(component, str(index + 10)),
                ingress(component, str(index + 20)),
            ]
        )
    return result


def pod(component: str) -> dict[str, object]:
    return {
        "apiVersion": "v1",
        "kind": "Pod",
        "metadata": {
            "name": f"{component}-pod",
            "namespace": NAMESPACE,
            "uid": f"{component}-uid",
        },
        "spec": {"nodeName": NODE_NAME},
        "status": {
            "conditions": [{"type": "Ready", "status": "True"}],
            "containerStatuses": [
                {"name": component, "ready": True, "restartCount": 0}
            ],
        },
    }


def endpoint_slice(component: str) -> dict[str, object]:
    return {
        "apiVersion": "discovery.k8s.io/v1",
        "kind": "EndpointSlice",
        "metadata": {"name": f"{component}-slice", "namespace": NAMESPACE},
        "endpoints": [
            {
                "addresses": [f"10.1.0.{len(component)}"],
                "conditions": {
                    "ready": True,
                    "serving": True,
                    "terminating": False,
                },
                "targetRef": {"uid": f"{component}-uid"},
            }
        ],
    }


class OracleHelmBaselineTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.protected_hashes = {path: file_hash(path) for path in PROTECTED_FILES}

    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory(
            prefix=".oracle-helm-baseline-test-", dir=REPO_DIR
        )
        self.root = Path(self.temp_dir.name)
        self.script_dir = self.root / ".scripts/kubernetes"
        self.script_dir.mkdir(parents=True)
        shutil.copy2(SCRIPT, self.script_dir / SCRIPT.name)
        (self.root / ".scripts/helm/charts/on-demand").mkdir(parents=True)

        self.bin_dir = self.root / "bin"
        self.bin_dir.mkdir()
        self.kubectl_log = self.root / "kubectl.log"
        self.helm_log = self.root / "helm.log"
        self.live_path = self.root / "live.json"
        self.client_path = self.root / "client.json"
        self.server_path = self.root / "server.json"
        self.stored_path = self.root / "stored.json"
        self.stored_manifest_path = self.root / "stored-manifest.yaml"
        self.nodes_path = self.root / "nodes.json"
        self.revision_path = self.root / "revision"
        self.deployment_get_count = self.root / "deployment-get-count"
        self.pod_dir = self.root / "pods"
        self.endpoint_dir = self.root / "endpoints"
        self.pod_dir.mkdir()
        self.endpoint_dir.mkdir()

        baseline_resources = resources()
        self.live_path.write_text(json.dumps(baseline_resources), encoding="utf-8")
        self.client_path.write_text(
            json.dumps(baseline_resources), encoding="utf-8"
        )
        self.server_path.write_text(
            json.dumps(baseline_resources), encoding="utf-8"
        )
        self.stored_path.write_text(
            json.dumps(baseline_resources), encoding="utf-8"
        )
        self.stored_manifest_path.write_text(
            "---\n# stored-release-manifest\napiVersion: apps/v1\n"
            "kind: Deployment\nmetadata:\n  name: oracle\n",
            encoding="utf-8",
        )
        self.nodes_path.write_text(
            json.dumps(
                {
                    "apiVersion": "v1",
                    "kind": "NodeList",
                    "items": [{"metadata": {"name": NODE_NAME}}],
                }
            ),
            encoding="utf-8",
        )
        self.revision_path.write_text("21", encoding="utf-8")
        for component in COMPONENTS:
            component_pods = [] if component == "guardian" else [pod(component)]
            component_endpoints = (
                [] if component == "guardian" else [endpoint_slice(component)]
            )
            (self.pod_dir / f"{component}.json").write_text(
                json.dumps(component_pods), encoding="utf-8"
            )
            (self.endpoint_dir / f"{component}.json").write_text(
                json.dumps(component_endpoints), encoding="utf-8"
            )

        (self.bin_dir / "kubectl").write_text(
            r'''#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path


def fail(code=64):
    raise SystemExit(code)


args = sys.argv[1:]
with Path(os.environ["KUBECTL_LOG"]).open("a", encoding="utf-8") as stream:
    stream.write(" ".join(args) + "\n")

if args == ["apply", "--help"]:
    print("--dry-run must be client or server --server-side")
    raise SystemExit(0)
if args == ["create", "--help"]:
    print("--dry-run must be client")
    raise SystemExit(0)
if args == ["config", "current-context"]:
    print(os.environ["TEST_CONTEXT"])
    raise SystemExit(0)

if args[:2] != ["--context", os.environ["TEST_CONTEXT"]]:
    fail(65)
args = args[2:]

if args == ["get", "nodes", "--output=json"]:
    print(Path(os.environ["NODES_PATH"]).read_text(encoding="utf-8"))
    raise SystemExit(0)

if len(args) >= 3 and args[:2] == ["auth", "can-i"]:
    print(os.environ.get("CAN_I", "yes"))
    raise SystemExit(0)

if len(args) >= 7 and args[:3] == ["--namespace", os.environ["NAMESPACE"], "get"]:
    resource_type = args[3]
    if resource_type in {"deployment", "service", "ingress"}:
        live = json.loads(Path(os.environ["LIVE_PATH"]).read_text(encoding="utf-8"))
        expected_kind = {
            "deployment": "Deployment",
            "service": "Service",
            "ingress": "Ingress",
        }[resource_type]
        items = [item for item in live if item["kind"] == expected_kind]
        if resource_type == "deployment":
            count_path = Path(os.environ["DEPLOYMENT_GET_COUNT"])
            count = int(count_path.read_text(encoding="utf-8")) if count_path.exists() else 0
            count += 1
            count_path.write_text(str(count), encoding="utf-8")
            if count == 2 and os.environ.get("DRIFT_ON_SECOND_GET") == "1":
                items[0]["metadata"]["resourceVersion"] = "drifted"
        print(json.dumps({"apiVersion": "v1", "kind": "List", "items": items}))
        raise SystemExit(0)
    if resource_type == "pods":
        selector = args[args.index("--selector") + 1]
        component = selector.removeprefix("app=")
        items = json.loads(
            (Path(os.environ["POD_DIR"]) / f"{component}.json").read_text(encoding="utf-8")
        )
        print(json.dumps({"apiVersion": "v1", "kind": "PodList", "items": items}))
        raise SystemExit(0)
    if resource_type == "endpointslice":
        selector = args[args.index("--selector") + 1]
        component = selector.removeprefix("kubernetes.io/service-name=")
        items = json.loads(
            (Path(os.environ["ENDPOINT_DIR"]) / f"{component}.json").read_text(encoding="utf-8")
        )
        print(
            json.dumps(
                {
                    "apiVersion": "discovery.k8s.io/v1",
                    "kind": "EndpointSliceList",
                    "items": items,
                }
            )
        )
        raise SystemExit(0)

if "create" in args and "--dry-run=client" in args:
    manifest = sys.stdin.read()
    if "payload-must-not-appear" in manifest:
        fail(69)
    path = "STORED_PATH" if "stored-release-manifest" in manifest else "CLIENT_PATH"
    items = json.loads(Path(os.environ[path]).read_text(encoding="utf-8"))
    print(json.dumps({"apiVersion": "v1", "kind": "List", "items": items}))
    raise SystemExit(0)

if "apply" in args and "--dry-run=server" in args:
    sys.stdin.read()
    items = json.loads(Path(os.environ["SERVER_PATH"]).read_text(encoding="utf-8"))
    print(json.dumps({"apiVersion": "v1", "kind": "List", "items": items}))
    raise SystemExit(0)

fail()
''',
            encoding="utf-8",
        )
        (self.bin_dir / "helm").write_text(
            r'''#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path


args = sys.argv[1:]
with Path(os.environ["HELM_LOG"]).open("a", encoding="utf-8") as stream:
    stream.write(" ".join(args) + "\n")

if args and args[0] == "upgrade" and "--values" in args:
    values_path = Path(args[args.index("--values") + 1])
    values = json.loads(values_path.read_text(encoding="utf-8"))
    oracle = values["components"]["oracle"]
    if oracle["keelDeploymentAnnotationsEnabled"] != (
        os.environ["EXPECTED_KEEL_DEPLOYMENT_ANNOTATIONS_ENABLED"] == "true"
    ):
        raise SystemExit(71)
    if oracle["candleCollection"] != {
        "enabled": True,
        "value": os.environ["CANDLE_SENTINEL"],
    }:
        raise SystemExit(66)
    if oracle["environmentSecret"] != {
        "enabled": True,
        "name": os.environ["ENVIRONMENT_SECRET_SENTINEL"],
        "optionalSet": os.environ["EXPECTED_ENVIRONMENT_SECRET_OPTIONAL"] == "true",
        "optional": os.environ["EXPECTED_ENVIRONMENT_SECRET_OPTIONAL"] == "true",
    }:
        raise SystemExit(67)
    if oracle["keelUpdateTime"] != {
        "enabled": os.environ["EXPECTED_KEEL_UPDATE_TIME_ENABLED"] == "true",
        "value": os.environ["EXPECTED_KEEL_UPDATE_TIME_VALUE"],
    }:
        raise SystemExit(70)
    if oracle["resources"]["limits"]["cpu"] != "4":
        raise SystemExit(68)

if args == ["upgrade", "--help"]:
    print("--dry-run client server --hide-secret --history-max --reuse-values --no-hooks")
    raise SystemExit(0)
if args and args[0] == "list":
    revision = int(Path(os.environ["REVISION_PATH"]).read_text(encoding="utf-8"))
    print(json.dumps([{"name": "sb-oracle-devnet", "revision": revision, "status": "deployed"}]))
    raise SystemExit(0)
if args[:3] == ["get", "manifest", "sb-oracle-devnet"]:
    print(Path(os.environ["STORED_MANIFEST_PATH"]).read_text(encoding="utf-8"), end="")
    raise SystemExit(0)
if args and args[0] == "upgrade" and "--dry-run=client" in args:
    if os.environ.get("HELM_RENDER_SECRET") == "1":
        print("MANIFEST:\n---\napiVersion: v1\nkind: Secret\nmetadata:\n  name: forbidden\n")
    elif os.environ["EXPECTED_KEEL_DEPLOYMENT_ANNOTATIONS_ENABLED"] == "false":
        shape = os.environ.get("HELM_KEEL_OPT_OUT_MANIFEST_SHAPE", "empty")
        annotation_shape = {
            "empty": "  annotations: {}\n",
            "absent": "",
            "null": "  annotations:\n",
            "retained": "  annotations:\n    keel.sh/policy: force\n",
        }.get(shape)
        if annotation_shape is None:
            raise SystemExit(73)
        print(
            "MANIFEST:\n---\napiVersion: apps/v1\nkind: Deployment\n"
            "metadata:\n  name: oracle\n"
            + annotation_shape
        )
    else:
        print("MANIFEST:\n---\napiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: oracle\n")
    raise SystemExit(0)
if args and args[0] == "upgrade":
    revision_path = Path(os.environ["REVISION_PATH"])
    revision = int(revision_path.read_text(encoding="utf-8"))
    revision_path.write_text(str(revision + 1), encoding="utf-8")
    if os.environ.get("POST_HELM_RESOURCE_VERSION_DRIFT") == "1":
        live_path = Path(os.environ["LIVE_PATH"])
        live = json.loads(live_path.read_text(encoding="utf-8"))
        live[0]["metadata"]["resourceVersion"] = "post-helm-drift"
        live_path.write_text(json.dumps(live), encoding="utf-8")
    mutation = os.environ.get("POST_HELM_MUTATION")
    if mutation:
        live_path = Path(os.environ["LIVE_PATH"])
        live = json.loads(live_path.read_text(encoding="utf-8"))
        deployments = {
            item["metadata"]["name"]: item
            for item in live
            if item["kind"] == "Deployment"
        }
        if mutation == "oracle-generation":
            deployments["oracle"]["metadata"]["generation"] += 1
        elif mutation == "oracle-generation-decrease":
            deployments["oracle"]["metadata"]["generation"] -= 1
        elif mutation == "oracle-generation-nonnumeric":
            deployments["oracle"]["metadata"]["generation"] = "invalid"
        elif mutation == "guardian-generation":
            deployments["guardian"]["metadata"]["generation"] += 1
        elif mutation == "oracle-service-generation":
            for resource in live:
                if (
                    resource["kind"] == "Service"
                    and resource["metadata"]["name"] == "oracle"
                ):
                    resource["metadata"]["generation"] = 1
                    break
            else:
                raise SystemExit(75)
        elif mutation == "oracle-spec":
            deployments["oracle"]["spec"]["minReadySeconds"] = 1
        elif mutation == "oracle-template":
            deployments["oracle"]["spec"]["template"]["metadata"]["annotations"][
                "example.com/unexpected"
            ] = "changed"
        elif mutation == "oracle-finalizer":
            deployments["oracle"]["metadata"]["finalizers"] = [
                "example.com/unexpected"
            ]
        elif mutation == "guardian-resource-version":
            deployments["guardian"]["metadata"]["resourceVersion"] = "changed"
        elif mutation == "oracle-pod":
            pod_path = Path(os.environ["POD_DIR"]) / "oracle.json"
            pods = json.loads(pod_path.read_text(encoding="utf-8"))
            pods[0]["status"]["containerStatuses"][0]["restartCount"] += 1
            pod_path.write_text(json.dumps(pods), encoding="utf-8")
        elif mutation == "oracle-endpoint":
            endpoint_path = Path(os.environ["ENDPOINT_DIR"]) / "oracle.json"
            endpoints = json.loads(endpoint_path.read_text(encoding="utf-8"))
            endpoints[0]["endpoints"][0]["conditions"]["ready"] = False
            endpoint_path.write_text(json.dumps(endpoints), encoding="utf-8")
        else:
            raise SystemExit(74)
        live_path.write_text(json.dumps(live), encoding="utf-8")
    print("upgrade output must stay suppressed")
    raise SystemExit(0)
raise SystemExit(64)
''',
            encoding="utf-8",
        )
        for path in (self.bin_dir / "kubectl", self.bin_dir / "helm"):
            path.chmod(0o755)

        self.environment = os.environ.copy()
        self.environment.update(
            {
                "PATH": f"{self.bin_dir}:{self.environment['PATH']}",
                "PYTHONDONTWRITEBYTECODE": "1",
                "KUBECTL_LOG": str(self.kubectl_log),
                "HELM_LOG": str(self.helm_log),
                "TEST_CONTEXT": CONTEXT,
                "NAMESPACE": NAMESPACE,
                "NODES_PATH": str(self.nodes_path),
                "LIVE_PATH": str(self.live_path),
                "CLIENT_PATH": str(self.client_path),
                "SERVER_PATH": str(self.server_path),
                "STORED_PATH": str(self.stored_path),
                "STORED_MANIFEST_PATH": str(self.stored_manifest_path),
                "REVISION_PATH": str(self.revision_path),
                "DEPLOYMENT_GET_COUNT": str(self.deployment_get_count),
                "POD_DIR": str(self.pod_dir),
                "ENDPOINT_DIR": str(self.endpoint_dir),
                "CANDLE_SENTINEL": CANDLE_SENTINEL,
                "ENVIRONMENT_SECRET_SENTINEL": ENVIRONMENT_SECRET_SENTINEL,
                "EXPECTED_ENVIRONMENT_SECRET_OPTIONAL": "false",
                "EXPECTED_KEEL_UPDATE_TIME_ENABLED": "false",
                "EXPECTED_KEEL_UPDATE_TIME_VALUE": "",
                "EXPECTED_KEEL_DEPLOYMENT_ANNOTATIONS_ENABLED": "true",
            }
        )

    def tearDown(self) -> None:
        self.temp_dir.cleanup()
        for path, expected in self.protected_hashes.items():
            self.assertEqual(file_hash(path), expected)

    def write_live(self, value: list[dict[str, object]]) -> None:
        self.live_path.write_text(json.dumps(value), encoding="utf-8")

    def write_client(self, value: list[dict[str, object]]) -> None:
        self.client_path.write_text(json.dumps(value), encoding="utf-8")

    def write_server(self, value: list[dict[str, object]]) -> None:
        self.server_path.write_text(json.dumps(value), encoding="utf-8")

    def write_stored(self, value: list[dict[str, object]]) -> None:
        self.stored_path.write_text(json.dumps(value), encoding="utf-8")

    def write_rendered(self, value: list[dict[str, object]]) -> None:
        self.write_client(value)
        self.write_server(value)

    def write_endpoint_slices(
        self, component: str, value: list[dict[str, object]]
    ) -> None:
        (self.endpoint_dir / f"{component}.json").write_text(
            json.dumps(value), encoding="utf-8"
        )

    def deployment_resource(
        self, value: list[dict[str, object]], component: str
    ) -> dict[str, object]:
        return next(
            item
            for item in value
            if item["kind"] == "Deployment" and item["metadata"]["name"] == component
        )

    def component_environment(
        self, value: list[dict[str, object]], component: str
    ) -> list[dict[str, object]]:
        deployment_value = self.deployment_resource(value, component)
        return deployment_value["spec"]["template"]["spec"]["containers"][0]["env"]

    def component_container(
        self, value: list[dict[str, object]], component: str
    ) -> dict[str, object]:
        deployment_value = self.deployment_resource(value, component)
        return deployment_value["spec"]["template"]["spec"]["containers"][0]

    def component_template_annotations(
        self, value: list[dict[str, object]], component: str
    ) -> dict[str, object]:
        deployment_value = self.deployment_resource(value, component)
        return deployment_value["spec"]["template"]["metadata"]["annotations"]

    def component_deployment_annotations(
        self, value: list[dict[str, object]], component: str
    ) -> dict[str, object]:
        deployment_value = self.deployment_resource(value, component)
        return deployment_value["metadata"]["annotations"]

    def add_oracle_keel_deployment_annotations(
        self, value: list[dict[str, object]]
    ) -> None:
        self.component_deployment_annotations(value, "oracle").update(
            ORACLE_KEEL_DEPLOYMENT_ANNOTATIONS
        )

    def select_target_host(self, host_id: str) -> None:
        node_name = {
            "stra01": NODE_NAME,
            "rbx01": RBX_NODE_NAME,
        }[host_id]
        self.nodes_path.write_text(
            json.dumps(
                {
                    "apiVersion": "v1",
                    "kind": "NodeList",
                    "items": [{"metadata": {"name": node_name}}],
                }
            ),
            encoding="utf-8",
        )
        for component in COMPONENTS:
            path = self.pod_dir / f"{component}.json"
            pods = json.loads(path.read_text(encoding="utf-8"))
            for pod_value in pods:
                pod_value["spec"]["nodeName"] = node_name
            path.write_text(json.dumps(pods), encoding="utf-8")

    def rbx_keel_opt_out_resources(
        self,
    ) -> tuple[
        list[dict[str, object]],
        list[dict[str, object]],
        list[dict[str, object]],
        list[dict[str, object]],
    ]:
        self.select_target_host("rbx01")
        self.environment["EXPECTED_KEEL_DEPLOYMENT_ANNOTATIONS_ENABLED"] = (
            "false"
        )
        live = resources()
        client = resources()
        stored = resources()
        self.remove_helm_ownership_metadata(client)
        self.remove_helm_ownership_metadata(stored)
        for component in COMPONENTS:
            annotations = self.component_deployment_annotations(live, component)
            annotations["deployment.kubernetes.io/revision"] = "7"
            annotations["kubernetes.io/change-cause"] = "rbx-baseline"
        server = copy.deepcopy(live)
        self.add_oracle_keel_deployment_annotations(stored)
        return live, client, stored, server

    def write_rbx_keel_opt_out_state(
        self,
        live: list[dict[str, object]],
        client: list[dict[str, object]],
        stored: list[dict[str, object]],
        server: list[dict[str, object]],
    ) -> None:
        self.write_live(live)
        self.write_client(client)
        self.write_stored(stored)
        self.write_server(server)

    def legacy_guardian_resources(
        self,
    ) -> tuple[
        list[dict[str, object]],
        list[dict[str, object]],
        list[dict[str, object]],
    ]:
        live = resources()
        guardian = self.deployment_resource(live, "guardian")
        guardian["metadata"]["labels"].pop("app")
        client = copy.deepcopy(live)
        server = copy.deepcopy(live)
        return live, client, server

    def remove_helm_ownership_metadata(
        self, value: list[dict[str, object]]
    ) -> None:
        for resource_value in value:
            metadata = resource_value["metadata"]
            metadata["labels"].pop("app.kubernetes.io/managed-by", None)
            metadata["annotations"].pop("meta.helm.sh/release-name", None)
            metadata["annotations"].pop(
                "meta.helm.sh/release-namespace", None
            )

    def remove_deployment_identity_labels(
        self, value: list[dict[str, object]]
    ) -> None:
        for component in COMPONENTS:
            labels = self.deployment_resource(value, component)["metadata"][
                "labels"
            ]
            for key in ("app", "chain", "cluster"):
                labels.pop(key, None)

    def live_only_ownership_resources(
        self,
    ) -> tuple[
        list[dict[str, object]],
        list[dict[str, object]],
        list[dict[str, object]],
        list[dict[str, object]],
    ]:
        live = resources()
        client = resources()
        stored = resources()
        self.remove_helm_ownership_metadata(client)
        self.remove_helm_ownership_metadata(stored)
        for component in COMPONENTS:
            self.deployment_resource(live, component)["metadata"]["annotations"][
                "deployment.kubernetes.io/revision"
            ] = "7"
        return live, client, stored, copy.deepcopy(live)

    def run_script(
        self,
        *extra: str,
        network: str = "devnet",
        host_id: str = "stra01",
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(self.script_dir / SCRIPT.name),
                "--network",
                network,
                "--host-id",
                host_id,
                "--expected-current-oracle-image",
                ORACLE_IMAGE,
                "--coordinator-exclusive-window-confirmed",
                *extra,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=self.environment,
            check=False,
        )

    def helm_lines(self) -> list[str]:
        if not self.helm_log.exists():
            return []
        return self.helm_log.read_text(encoding="utf-8").splitlines()

    def applied_upgrade_lines(self) -> list[str]:
        return [
            line
            for line in self.helm_lines()
            if line.startswith("upgrade sb-oracle-devnet ")
            and "--dry-run=" not in line
        ]

    def dry_run_upgrade_lines(self) -> list[str]:
        return [
            line
            for line in self.helm_lines()
            if line.startswith("upgrade sb-oracle-devnet ")
            and "--dry-run=client" in line
        ]

    def test_guardian_zero_plan_is_secret_safe_and_non_mutating(self) -> None:
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("resourceSpecsEquivalent=true hash=", result.stdout)
        self.assertIn("podTemplatesEquivalent=true hash=", result.stdout)
        self.assertIn("secretReferencesEquivalent=true hash=", result.stdout)
        self.assertIn("environmentOrdersEquivalent=true hash=", result.stdout)
        self.assertIn("activePodsStable=true hash=", result.stdout)
        self.assertIn("action=planned", result.stdout)
        self.assertEqual(self.applied_upgrade_lines(), [])
        combined = result.stdout + result.stderr
        for forbidden in (
            PAYER_KEY,
            SUI_NAME,
            SUI_KEY,
            POLICY_SENTINEL,
            CANDLE_SENTINEL,
            ENVIRONMENT_SECRET_SENTINEL,
        ):
            self.assertNotIn(forbidden, combined)

    def test_stored_manifest_allows_safe_image_and_replica_scalar_drift(
        self,
    ) -> None:
        stored = resources()
        for component in COMPONENTS:
            self.component_container(stored, component)["image"] = (
                f"docker.io/switchboardlabs/{component}:legacy"
            )
            self.component_container(stored, component)["resources"]["limits"][
                "cpu"
            ] = "4000m"
        self.deployment_resource(stored, "guardian")["spec"]["replicas"] = 1
        self.write_stored(stored)

        result = self.run_script()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("helmPatchDeletionFree=true hash=", result.stdout)
        self.assertIn("action=planned", result.stdout)
        self.assertIn(
            "get manifest sb-oracle-devnet --kube-context test-context "
            "--namespace switchboard-oracle-devnet --revision 21",
            self.helm_lines(),
        )
        client_parse_lines = [
            line
            for line in self.kubectl_log.read_text(encoding="utf-8").splitlines()
            if "--dry-run=client" in line
        ]
        self.assertEqual(len(client_parse_lines), 2)
        self.assertTrue(all(" create " in line for line in client_parse_lines))
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_stored_manifest_rejects_non_equivalent_cpu_change(self) -> None:
        stored = resources()
        self.component_container(stored, "oracle")["resources"]["limits"][
            "cpu"
        ] = "3000m"
        self.write_stored(stored)

        result = self.run_script("--apply")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsupported old-to-new change", result.stderr)
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_stored_manifest_allows_named_environment_order_only_drift(
        self,
    ) -> None:
        stored = resources()
        environment = self.component_environment(stored, "oracle")
        environment[:] = environment[2:] + environment[:2]
        self.write_stored(stored)

        result = self.run_script()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("helmPatchDeletionFree=true hash=", result.stdout)
        self.assertIn("action=planned", result.stdout)
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_client_environment_order_change_is_rejected(self) -> None:
        client = resources()
        environment = self.component_environment(client, "oracle")
        environment[:] = environment[2:] + environment[:2]
        self.write_client(client)

        result = self.run_script("--apply")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("reorder a protected container environment", result.stderr)
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_stored_manifest_allows_missing_sui_secret_reference_addition(
        self,
    ) -> None:
        stored = resources()
        environment = self.component_environment(stored, "oracle")
        environment[:] = [
            item for item in environment if item["name"] != "SUI_MAINNET_RPC"
        ]
        self.write_stored(stored)

        result = self.run_script()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("helmPatchDeletionFree=true hash=", result.stdout)
        self.assertIn("action=planned", result.stdout)
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_stored_manifest_rejects_arbitrary_new_environment_addition(self) -> None:
        live = resources()
        self.component_environment(live, "oracle").append(
            {"name": "UNAUTHORIZED_ADDITION", "value": "unchanged-live-value"}
        )
        self.write_live(live)
        self.write_rendered(copy.deepcopy(live))
        self.write_stored(resources())

        result = self.run_script("--apply")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsupported old-to-new change", result.stderr)
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_stored_manifest_allows_environment_secret_becoming_optional(
        self,
    ) -> None:
        stored = resources()
        client = resources()
        live = resources()
        for value in (client, live):
            self.component_container(value, "oracle")["envFrom"][0]["secretRef"][
                "optional"
            ] = True
        self.write_stored(stored)
        self.write_live(live)
        self.write_rendered(client)
        self.environment["EXPECTED_ENVIRONMENT_SECRET_OPTIONAL"] = "true"

        result = self.run_script()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("helmPatchDeletionFree=true hash=", result.stdout)
        self.assertIn("action=planned", result.stdout)

    def test_stored_manifest_rejects_environment_secret_becoming_required(
        self,
    ) -> None:
        stored = resources()
        client = resources()
        live = resources()
        self.component_container(stored, "oracle")["envFrom"][0]["secretRef"][
            "optional"
        ] = True
        self.write_stored(stored)
        self.write_live(live)
        self.write_rendered(client)

        result = self.run_script("--apply")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsupported old-to-new change", result.stderr)
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_stored_manifest_allows_only_empty_to_devnet_cluster_label(self) -> None:
        stored = resources()
        for component in COMPONENTS:
            self.deployment_resource(stored, component)["metadata"]["labels"][
                "cluster"
            ] = ""
        self.write_stored(stored)

        result = self.run_script()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("helmPatchDeletionFree=true hash=", result.stdout)
        self.assertIn("action=planned", result.stdout)

    def test_stored_manifest_rejects_other_cluster_label_change(self) -> None:
        stored = resources()
        self.deployment_resource(stored, "oracle")["metadata"]["labels"][
            "cluster"
        ] = "unexpected"
        self.write_stored(stored)

        result = self.run_script("--apply")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsupported old-to-new change", result.stderr)
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_stored_manifest_old_only_map_field_blocks_before_server_dry_run(
        self,
    ) -> None:
        stored = resources()
        guardian = self.deployment_resource(stored, "guardian")
        guardian["metadata"]["annotations"]["legacy.example/old-only"] = "present"
        self.write_stored(stored)

        result = self.run_script("--apply")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsupported old-to-new change", result.stderr)
        self.assertFalse(
            any(
                "--dry-run=server" in line
                for line in self.kubectl_log.read_text().splitlines()
            )
        )
        self.assertEqual(self.applied_upgrade_lines(), [])
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")

    def test_stored_manifest_old_only_merge_list_entry_blocks_before_apply(
        self,
    ) -> None:
        stored = resources()
        self.component_environment(stored, "gateway").append(
            {"name": "OLD_ONLY", "value": "removed"}
        )
        self.write_stored(stored)

        result = self.run_script("--apply")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsupported old-to-new change", result.stderr)
        self.assertEqual(self.applied_upgrade_lines(), [])
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")

    def test_stored_oracle_environment_contract_cannot_be_deleted(self) -> None:
        for removed_field in ("CANDLE_COLLECTION_ENABLED", "envFrom"):
            with self.subTest(removed_field=removed_field):
                client = resources()
                oracle_container = self.component_container(client, "oracle")
                if removed_field == "envFrom":
                    del oracle_container["envFrom"]
                else:
                    oracle_container["env"] = [
                        item
                        for item in oracle_container["env"]
                        if item["name"] != removed_field
                    ]
                self.write_client(client)
                self.write_server(resources())
                self.write_stored(resources())

                result = self.run_script("--apply")

                self.assertNotEqual(result.returncode, 0)
                expected_error = (
                    "reorder a protected container environment"
                    if removed_field == "CANDLE_COLLECTION_ENABLED"
                    else "unsupported old-to-new change"
                )
                self.assertIn(expected_error, result.stderr)
                self.assertEqual(self.applied_upgrade_lines(), [])
                self.assertEqual(
                    self.revision_path.read_text(encoding="utf-8"), "21"
                )

    def test_client_subset_accepts_api_defaults(
        self,
    ) -> None:
        live = resources()
        client = copy.deepcopy(live)
        for component in COMPONENTS:
            live_deployment = self.deployment_resource(live, component)
            live_deployment["spec"]["progressDeadlineSeconds"] = 600
            client_service = next(
                item
                for item in client
                if item["kind"] == "Service"
                and item["metadata"]["name"] == component
            )
            client_service["spec"].pop("clusterIP")
            client_service["spec"].pop("type")
        self.write_live(live)
        self.write_client(client)
        self.write_stored(copy.deepcopy(client))
        self.write_server(copy.deepcopy(live))

        result = self.run_script()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("action=planned", result.stdout)
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_exact_live_oracle_keel_update_time_is_preserved(self) -> None:
        live = resources()
        client = resources()
        stored = resources()
        server = resources()
        for value in (live, client, server):
            self.component_template_annotations(value, "oracle")[
                "keel.sh/update-time"
            ] = KEEL_UPDATE_TIME_SENTINEL
        self.environment["EXPECTED_KEEL_UPDATE_TIME_ENABLED"] = "true"
        self.environment["EXPECTED_KEEL_UPDATE_TIME_VALUE"] = (
            KEEL_UPDATE_TIME_SENTINEL
        )
        self.write_live(live)
        self.write_client(client)
        self.write_stored(stored)
        self.write_server(server)

        result = self.run_script("--apply")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("postApplyResourceVersionsUnchanged=true", result.stdout)
        self.assertIn(
            "postApplyPodUidsRestartsReadinessUnchanged=true", result.stdout
        )
        self.assertEqual(len(self.applied_upgrade_lines()), 1)
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "22")
        outputs = (
            result.stdout,
            result.stderr,
            self.helm_log.read_text(encoding="utf-8"),
            self.kubectl_log.read_text(encoding="utf-8"),
        )
        self.assertTrue(
            all(KEEL_UPDATE_TIME_SENTINEL not in output for output in outputs)
        )

    def test_stored_exact_oracle_keel_update_time_is_preserved(self) -> None:
        live = resources()
        self.component_template_annotations(live, "oracle")[
            "keel.sh/update-time"
        ] = KEEL_UPDATE_TIME_SENTINEL
        self.environment["EXPECTED_KEEL_UPDATE_TIME_ENABLED"] = "true"
        self.environment["EXPECTED_KEEL_UPDATE_TIME_VALUE"] = (
            KEEL_UPDATE_TIME_SENTINEL
        )
        self.write_live(live)
        self.write_client(copy.deepcopy(live))
        self.write_stored(copy.deepcopy(live))
        self.write_server(copy.deepcopy(live))

        result = self.run_script()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("action=planned", result.stdout)
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_invalid_live_keel_update_time_blocks_before_helm(self) -> None:
        cases = (
            ("oracle", 7),
            ("guardian", "unexpected"),
            ("gateway", "unexpected"),
        )
        for component, annotation_value in cases:
            with self.subTest(component=component, value=annotation_value):
                live = resources()
                self.component_template_annotations(live, component)[
                    "keel.sh/update-time"
                ] = annotation_value
                self.write_live(live)
                self.revision_path.write_text("21", encoding="utf-8")

                result = self.run_script("--apply")

                self.assertNotEqual(result.returncode, 0)
                self.assertIn(
                    "keel update-time annotation state is invalid", result.stderr
                )
                self.assertEqual(self.applied_upgrade_lines(), [])
                self.assertEqual(
                    self.revision_path.read_text(encoding="utf-8"), "21"
                )

    def test_rendered_keel_update_time_mismatch_blocks_before_helm(self) -> None:
        cases = ("remove", "add", "change")
        for case in cases:
            with self.subTest(case=case):
                live = resources()
                client = resources()
                if case in {"remove", "change"}:
                    self.component_template_annotations(live, "oracle")[
                        "keel.sh/update-time"
                    ] = "live value"
                    self.environment["EXPECTED_KEEL_UPDATE_TIME_ENABLED"] = "true"
                    self.environment["EXPECTED_KEEL_UPDATE_TIME_VALUE"] = "live value"
                else:
                    self.environment["EXPECTED_KEEL_UPDATE_TIME_ENABLED"] = "false"
                    self.environment["EXPECTED_KEEL_UPDATE_TIME_VALUE"] = ""
                if case in {"add", "change"}:
                    self.component_template_annotations(client, "oracle")[
                        "keel.sh/update-time"
                    ] = "rendered value"
                self.write_live(live)
                self.write_client(client)
                self.write_server(copy.deepcopy(client))
                self.revision_path.write_text("21", encoding="utf-8")

                result = self.run_script("--apply")

                self.assertNotEqual(result.returncode, 0)
                self.assertIn(
                    "would change Deployment template annotations", result.stderr
                )
                self.assertEqual(self.applied_upgrade_lines(), [])
                self.assertEqual(
                    self.revision_path.read_text(encoding="utf-8"), "21"
                )

    def test_other_template_annotation_mismatch_blocks_before_helm(self) -> None:
        cases = ("remove", "add", "change")
        for case in cases:
            with self.subTest(case=case):
                live = resources()
                client = resources()
                if case in {"remove", "change"}:
                    self.component_template_annotations(live, "oracle")[
                        "example.com/protected"
                    ] = "live value"
                if case in {"add", "change"}:
                    self.component_template_annotations(client, "oracle")[
                        "example.com/protected"
                    ] = "rendered value"
                self.write_live(live)
                self.write_client(client)
                self.write_server(copy.deepcopy(client))
                self.revision_path.write_text("21", encoding="utf-8")

                result = self.run_script("--apply")

                self.assertNotEqual(result.returncode, 0)
                self.assertIn(
                    "would change Deployment template annotations", result.stderr
                )
                self.assertEqual(self.applied_upgrade_lines(), [])
                self.assertEqual(
                    self.revision_path.read_text(encoding="utf-8"), "21"
                )

    def test_stored_template_annotation_drift_blocks_before_helm(self) -> None:
        cases = ("changed-keel", "removed-keel", "other-addition")
        for case in cases:
            with self.subTest(case=case):
                self.environment["EXPECTED_KEEL_UPDATE_TIME_ENABLED"] = "false"
                self.environment["EXPECTED_KEEL_UPDATE_TIME_VALUE"] = ""
                live = resources()
                client = resources()
                stored = resources()
                server = resources()
                if case in {"changed-keel", "removed-keel"}:
                    self.component_template_annotations(stored, "oracle")[
                        "keel.sh/update-time"
                    ] = "stored value"
                if case == "changed-keel":
                    for value in (live, client, server):
                        self.component_template_annotations(value, "oracle")[
                            "keel.sh/update-time"
                        ] = "live value"
                    self.environment["EXPECTED_KEEL_UPDATE_TIME_ENABLED"] = "true"
                    self.environment["EXPECTED_KEEL_UPDATE_TIME_VALUE"] = "live value"
                elif case == "other-addition":
                    for value in (live, client, server):
                        self.component_template_annotations(value, "oracle")[
                            "example.com/protected"
                        ] = "new value"
                self.write_live(live)
                self.write_client(client)
                self.write_stored(stored)
                self.write_server(server)
                self.revision_path.write_text("21", encoding="utf-8")

                result = self.run_script("--apply")

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("unsupported old-to-new change", result.stderr)
                self.assertEqual(self.applied_upgrade_lines(), [])
                self.assertEqual(
                    self.revision_path.read_text(encoding="utf-8"), "21"
                )

    def test_server_keel_update_time_mismatch_blocks_before_helm(self) -> None:
        cases = ("omit", "change", "add")
        for case in cases:
            with self.subTest(case=case):
                live = resources()
                client = resources()
                server = resources()
                if case in {"omit", "change"}:
                    for value in (live, client):
                        self.component_template_annotations(value, "oracle")[
                            "keel.sh/update-time"
                        ] = "live value"
                    self.environment["EXPECTED_KEEL_UPDATE_TIME_ENABLED"] = "true"
                    self.environment["EXPECTED_KEEL_UPDATE_TIME_VALUE"] = "live value"
                else:
                    self.environment["EXPECTED_KEEL_UPDATE_TIME_ENABLED"] = "false"
                    self.environment["EXPECTED_KEEL_UPDATE_TIME_VALUE"] = ""
                if case in {"change", "add"}:
                    self.component_template_annotations(server, "oracle")[
                        "keel.sh/update-time"
                    ] = "server value"
                self.write_live(live)
                self.write_client(client)
                self.write_server(server)
                self.revision_path.write_text("21", encoding="utf-8")

                result = self.run_script("--apply")

                self.assertNotEqual(result.returncode, 0)
                self.assertIn(
                    "server dry-run would change a protected resource spec",
                    result.stderr,
                )
                self.assertEqual(self.applied_upgrade_lines(), [])
                self.assertEqual(
                    self.revision_path.read_text(encoding="utf-8"), "21"
                )

    def test_default_rbx_keel_deployment_annotations_remain_enabled(self) -> None:
        self.select_target_host("rbx01")

        result = self.run_script(host_id="rbx01")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("action=planned", result.stdout)
        self.assertFalse(
            any(
                " patch " in line
                for line in self.kubectl_log.read_text(encoding="utf-8").splitlines()
            )
        )
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_keel_deployment_annotation_opt_out_is_rbx01_devnet_only(
        self,
    ) -> None:
        cases = (
            ("mainnet", "rbx01", "devnet-only"),
            ("devnet", "stra01", "restricted to rbx01 devnet"),
        )
        for network, host_id, expected_error in cases:
            with self.subTest(network=network, host_id=host_id):
                result = self.run_script(
                    "--disable-oracle-keel-deployment-annotations",
                    network=network,
                    host_id=host_id,
                )

                self.assertNotEqual(result.returncode, 0)
                self.assertIn(expected_error, result.stderr)
                self.assertEqual(self.helm_lines(), [])
                self.assertFalse(self.kubectl_log.exists())

    def test_keel_opt_out_requires_all_live_annotations_absent(self) -> None:
        for annotation, value in ORACLE_KEEL_DEPLOYMENT_ANNOTATIONS.items():
            with self.subTest(annotation=annotation):
                live, client, stored, server = self.rbx_keel_opt_out_resources()
                self.component_deployment_annotations(live, "oracle")[
                    annotation
                ] = value
                self.write_rbx_keel_opt_out_state(live, client, stored, server)
                self.revision_path.write_text("21", encoding="utf-8")

                result = self.run_script(
                    "--disable-oracle-keel-deployment-annotations",
                    "--apply",
                    host_id="rbx01",
                )

                self.assertNotEqual(result.returncode, 0)
                self.assertIn(
                    "Oracle Keel Deployment annotations must already be absent",
                    result.stderr,
                )
                self.assertEqual(self.applied_upgrade_lines(), [])
                self.assertEqual(
                    self.revision_path.read_text(encoding="utf-8"), "21"
                )

    def test_rbx_keel_opt_out_apply_is_a_metadata_only_record(self) -> None:
        live, client, stored, server = self.rbx_keel_opt_out_resources()
        self.deployment_resource(client, "oracle")["metadata"].pop(
            "annotations"
        )
        for value in (live, client, server):
            self.component_template_annotations(value, "oracle")[
                "keel.sh/update-time"
            ] = KEEL_UPDATE_TIME_SENTINEL
        self.environment["EXPECTED_KEEL_UPDATE_TIME_ENABLED"] = "true"
        self.environment["EXPECTED_KEEL_UPDATE_TIME_VALUE"] = (
            KEEL_UPDATE_TIME_SENTINEL
        )
        self.environment["POST_HELM_RESOURCE_VERSION_DRIFT"] = "1"
        self.environment["POST_HELM_MUTATION"] = "oracle-generation"
        self.write_rbx_keel_opt_out_state(live, client, stored, server)

        result = self.run_script(
            "--disable-oracle-keel-deployment-annotations",
            "--apply",
            host_id="rbx01",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            "oracleKeelStoredDeletionRestricted=true hash=", result.stdout
        )
        self.assertIn(
            "postApplyOracleResourceVersionChanged=true", result.stdout
        )
        self.assertIn(
            "postApplyOtherResourceVersionsUnchanged=true", result.stdout
        )
        self.assertIn("postApplyOracleMetadataOnlyRecord=true", result.stdout)
        self.assertIn(
            "postApplyOracleGenerationAdvanced=true", result.stdout
        )
        self.assertIn(
            "postApplyOtherDeploymentGenerationsUnchanged=true", result.stdout
        )
        self.assertIn(
            "postApplyNonvolatileMetadataUnchanged=true", result.stdout
        )
        self.assertIn(
            "postApplyPodUidsRestartsReadinessUnchanged=true", result.stdout
        )
        self.assertIn("postApplyEndpointsUnchanged=true", result.stdout)
        self.assertEqual(len(self.applied_upgrade_lines()), 1)
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "22")
        combined = result.stdout + result.stderr
        for forbidden in (
            PAYER_KEY,
            SUI_NAME,
            SUI_KEY,
            POLICY_SENTINEL,
            CANDLE_SENTINEL,
            ENVIRONMENT_SECRET_SENTINEL,
            KEEL_UPDATE_TIME_SENTINEL,
        ):
            self.assertNotIn(forbidden, combined)

    def assert_rbx_post_helm_mutation_rejected(
        self,
        mutation: str,
        expected_error: str,
        *,
        initial_oracle_generation: int | None = None,
    ) -> None:
        live, client, stored, server = self.rbx_keel_opt_out_resources()
        if initial_oracle_generation is not None:
            self.deployment_resource(live, "oracle")["metadata"][
                "generation"
            ] = initial_oracle_generation
        self.write_rbx_keel_opt_out_state(live, client, stored, server)
        self.environment["POST_HELM_RESOURCE_VERSION_DRIFT"] = "1"
        self.environment["POST_HELM_MUTATION"] = mutation

        result = self.run_script(
            "--disable-oracle-keel-deployment-annotations",
            "--apply",
            host_id="rbx01",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(expected_error, result.stderr)
        self.assertIn(
            "requires-secret-safe-Helm-revision-readback", result.stderr
        )
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "22")
        self.assertEqual(len(self.applied_upgrade_lines()), 1)

    def test_keel_opt_out_rejects_oracle_generation_decrease(self) -> None:
        self.assert_rbx_post_helm_mutation_rejected(
            "oracle-generation-decrease",
            "Oracle Deployment generation decreased",
            initial_oracle_generation=2,
        )

    def test_keel_opt_out_rejects_nonnumeric_oracle_generation(self) -> None:
        self.assert_rbx_post_helm_mutation_rejected(
            "oracle-generation-nonnumeric",
            "Deployment generation is missing or invalid",
        )

    def test_keel_opt_out_rejects_other_deployment_generation_drift(self) -> None:
        self.assert_rbx_post_helm_mutation_rejected(
            "guardian-generation",
            "non-Oracle Deployment generation changed",
        )

    def test_keel_opt_out_rejects_other_resource_generation_drift(self) -> None:
        self.assert_rbx_post_helm_mutation_rejected(
            "oracle-service-generation",
            "protected resource metadata changed",
        )

    def test_keel_opt_out_rejects_post_helm_spec_drift(self) -> None:
        self.assert_rbx_post_helm_mutation_rejected(
            "oracle-spec",
            "protected resource spec changed",
        )

    def test_keel_opt_out_rejects_post_helm_template_drift(self) -> None:
        self.assert_rbx_post_helm_mutation_rejected(
            "oracle-template",
            "protected resource spec changed",
        )

    def test_keel_opt_out_rejects_post_helm_metadata_drift(self) -> None:
        self.assert_rbx_post_helm_mutation_rejected(
            "oracle-finalizer",
            "protected resource metadata changed",
        )

    def test_keel_opt_out_rejects_other_resource_version_drift(self) -> None:
        self.assert_rbx_post_helm_mutation_rejected(
            "guardian-resource-version",
            "non-Oracle resourceVersion changed",
        )

    def test_keel_opt_out_rejects_post_helm_pod_drift(self) -> None:
        self.assert_rbx_post_helm_mutation_rejected(
            "oracle-pod",
            "active pod identity or health changed",
        )

    def test_keel_opt_out_rejects_post_helm_endpoint_drift(self) -> None:
        self.assert_rbx_post_helm_mutation_rejected(
            "oracle-endpoint",
            "ready endpoint count does not equal Deployment replicas",
        )

    def test_keel_opt_out_rejects_noncanonical_stored_annotations(self) -> None:
        for case in ("missing", "wrong-value"):
            with self.subTest(case=case):
                live, client, stored, server = self.rbx_keel_opt_out_resources()
                annotations = self.component_deployment_annotations(
                    stored, "oracle"
                )
                if case == "missing":
                    annotations.pop("keel.sh/policy")
                else:
                    annotations["keel.sh/policy"] = "unexpected"
                self.write_rbx_keel_opt_out_state(live, client, stored, server)
                self.revision_path.write_text("21", encoding="utf-8")

                result = self.run_script(
                    "--disable-oracle-keel-deployment-annotations",
                    "--apply",
                    host_id="rbx01",
                )

                self.assertNotEqual(result.returncode, 0)
                self.assertIn(
                    "unsupported Oracle Keel annotation transition",
                    result.stderr,
                )
                self.assertEqual(self.applied_upgrade_lines(), [])
                self.assertEqual(
                    self.revision_path.read_text(encoding="utf-8"), "21"
                )

    def test_keel_opt_out_rejects_rendered_or_server_readdition(self) -> None:
        for source in ("rendered", "server"):
            with self.subTest(source=source):
                live, client, stored, server = self.rbx_keel_opt_out_resources()
                target = client if source == "rendered" else server
                self.component_deployment_annotations(target, "oracle")[
                    "keel.sh/policy"
                ] = "force"
                self.write_rbx_keel_opt_out_state(live, client, stored, server)
                self.revision_path.write_text("21", encoding="utf-8")

                result = self.run_script(
                    "--disable-oracle-keel-deployment-annotations",
                    "--apply",
                    host_id="rbx01",
                )

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("would change protected resource metadata", result.stderr)
                self.assertEqual(self.applied_upgrade_lines(), [])
                self.assertEqual(
                    self.revision_path.read_text(encoding="utf-8"), "21"
                )

    def test_keel_opt_out_raw_empty_annotation_map_is_required(self) -> None:
        for shape in ("absent", "null", "retained"):
            with self.subTest(shape=shape):
                live, client, stored, server = self.rbx_keel_opt_out_resources()
                self.write_rbx_keel_opt_out_state(live, client, stored, server)
                self.environment["HELM_KEEL_OPT_OUT_MANIFEST_SHAPE"] = shape
                self.revision_path.write_text("21", encoding="utf-8")

                result = self.run_script(
                    "--disable-oracle-keel-deployment-annotations",
                    "--apply",
                    host_id="rbx01",
                )

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Oracle Keel annotation opt-out manifest", result.stderr)
                self.assertEqual(self.applied_upgrade_lines(), [])
                self.assertEqual(
                    self.revision_path.read_text(encoding="utf-8"), "21"
                )

    def test_keel_opt_out_does_not_allow_arbitrary_annotation_deletion(
        self,
    ) -> None:
        live, client, stored, server = self.rbx_keel_opt_out_resources()
        self.component_deployment_annotations(stored, "guardian")[
            "example.com/old-only"
        ] = "present"
        self.write_rbx_keel_opt_out_state(live, client, stored, server)

        result = self.run_script(
            "--disable-oracle-keel-deployment-annotations",
            "--apply",
            host_id="rbx01",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsupported old-to-new change", result.stderr)
        self.assertEqual(self.applied_upgrade_lines(), [])
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")

    def test_keel_annotation_deletion_without_opt_out_blocks(self) -> None:
        stored = resources()
        self.add_oracle_keel_deployment_annotations(stored)
        self.write_stored(stored)

        result = self.run_script("--apply")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsupported old-to-new change", result.stderr)
        self.assertEqual(self.applied_upgrade_lines(), [])
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")

    def test_exact_live_only_helm_and_controller_metadata_is_preserved(
        self,
    ) -> None:
        live, client, stored, server = self.live_only_ownership_resources()
        self.write_live(live)
        self.write_client(client)
        self.write_stored(stored)
        self.write_server(server)

        result = self.run_script("--apply")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("resourceMetadataEquivalent=true hash=", result.stdout)
        self.assertIn("postApplyResourceVersionsUnchanged=true", result.stdout)
        self.assertIn("action=baseline-recorded", result.stdout)
        self.assertEqual(len(self.applied_upgrade_lines()), 1)
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "22")

    def test_exact_live_only_deployment_change_cause_is_preserved(self) -> None:
        live = resources()
        client = resources()
        stored = resources()
        self.deployment_resource(live, "oracle")["metadata"]["annotations"][
            "kubernetes.io/change-cause"
        ] = "preserve this exact live value"
        self.write_live(live)
        self.write_client(client)
        self.write_stored(stored)
        self.write_server(copy.deepcopy(live))

        result = self.run_script("--apply")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("resourceMetadataEquivalent=true hash=", result.stdout)
        self.assertIn("postApplyResourceVersionsUnchanged=true", result.stdout)
        self.assertEqual(len(self.applied_upgrade_lines()), 1)
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "22")

    def test_change_cause_on_service_or_ingress_blocks_before_helm(self) -> None:
        for kind in ("Service", "Ingress"):
            with self.subTest(kind=kind):
                live = resources()
                resource = next(item for item in live if item["kind"] == kind)
                resource["metadata"]["annotations"][
                    "kubernetes.io/change-cause"
                ] = "unsupported resource"
                self.write_live(live)
                self.write_server(copy.deepcopy(live))
                self.revision_path.write_text("21", encoding="utf-8")

                result = self.run_script("--apply")

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("unsupported kubernetes.io/change-cause", result.stderr)
                self.assertEqual(self.applied_upgrade_lines(), [])
                self.assertEqual(
                    self.revision_path.read_text(encoding="utf-8"), "21"
                )

    def test_change_cause_in_stored_or_rendered_metadata_blocks_before_helm(
        self,
    ) -> None:
        cases = (
            ("stored", "live value", None),
            ("rendered", None, "live value"),
            ("both", "live value", "live value"),
            ("changed", "stored value", "rendered value"),
        )
        for case, stored_value, rendered_value in cases:
            with self.subTest(case=case):
                live = resources()
                client = resources()
                stored = resources()
                self.deployment_resource(live, "oracle")["metadata"][
                    "annotations"
                ]["kubernetes.io/change-cause"] = "live value"
                if stored_value is not None:
                    self.deployment_resource(stored, "oracle")["metadata"][
                        "annotations"
                    ]["kubernetes.io/change-cause"] = stored_value
                if rendered_value is not None:
                    self.deployment_resource(client, "oracle")["metadata"][
                        "annotations"
                    ]["kubernetes.io/change-cause"] = rendered_value
                self.write_live(live)
                self.write_client(client)
                self.write_stored(stored)
                self.write_server(copy.deepcopy(live))
                self.revision_path.write_text("21", encoding="utf-8")

                result = self.run_script("--apply")

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("unsupported kubernetes.io/change-cause", result.stderr)
                self.assertEqual(self.applied_upgrade_lines(), [])
                self.assertEqual(
                    self.revision_path.read_text(encoding="utf-8"), "21"
                )

    def test_server_cannot_omit_change_or_add_change_cause(self) -> None:
        cases = ("omit", "change", "add")
        for case in cases:
            with self.subTest(case=case):
                live = resources()
                client = resources()
                stored = resources()
                server = copy.deepcopy(live)
                if case in {"omit", "change"}:
                    self.deployment_resource(live, "oracle")["metadata"][
                        "annotations"
                    ]["kubernetes.io/change-cause"] = "live value"
                if case == "change":
                    self.deployment_resource(server, "oracle")["metadata"][
                        "annotations"
                    ]["kubernetes.io/change-cause"] = "changed value"
                elif case == "add":
                    self.deployment_resource(server, "oracle")["metadata"][
                        "annotations"
                    ]["kubernetes.io/change-cause"] = "server-only value"
                self.write_live(live)
                self.write_client(client)
                self.write_stored(stored)
                self.write_server(server)
                self.revision_path.write_text("21", encoding="utf-8")

                result = self.run_script("--apply")

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("server dry-run would change protected", result.stderr)
                self.assertEqual(self.applied_upgrade_lines(), [])
                self.assertEqual(
                    self.revision_path.read_text(encoding="utf-8"), "21"
                )

    def test_server_cannot_add_change_cause_to_service_or_ingress(self) -> None:
        for kind in ("Service", "Ingress"):
            with self.subTest(kind=kind):
                server = resources()
                resource = next(item for item in server if item["kind"] == kind)
                resource["metadata"]["annotations"][
                    "kubernetes.io/change-cause"
                ] = "server-only value"
                self.write_server(server)
                self.revision_path.write_text("21", encoding="utf-8")

                result = self.run_script("--apply")

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("server dry-run would change protected", result.stderr)
                self.assertEqual(self.applied_upgrade_lines(), [])
                self.assertEqual(
                    self.revision_path.read_text(encoding="utf-8"), "21"
                )

    def test_requested_deployment_labels_missing_live_block_before_helm(
        self,
    ) -> None:
        live = resources()
        self.remove_deployment_identity_labels(live)
        self.write_live(live)

        result = self.run_script("--apply")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("would change protected resource metadata", result.stderr)
        self.assertEqual(self.applied_upgrade_lines(), [])
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")

    def test_unrequested_live_only_deployment_labels_block_before_helm(
        self,
    ) -> None:
        client = resources()
        stored = resources()
        self.remove_deployment_identity_labels(client)
        self.remove_deployment_identity_labels(stored)
        self.write_client(client)
        self.write_stored(stored)

        result = self.run_script("--apply")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("would change protected resource metadata", result.stderr)
        self.assertEqual(self.applied_upgrade_lines(), [])
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")

    def test_unexpected_live_only_metadata_blocks_before_helm(self) -> None:
        live = resources()
        gateway = self.deployment_resource(live, "gateway")
        gateway["metadata"]["annotations"][
            "controller.example/unexpected"
        ] = "preserved-live-only"
        self.write_live(live)

        result = self.run_script("--apply")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("would change protected resource metadata", result.stderr)
        self.assertEqual(self.applied_upgrade_lines(), [])
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")

    def test_server_cannot_change_live_only_helm_metadata(self) -> None:
        live, client, stored, server = self.live_only_ownership_resources()
        self.deployment_resource(server, "oracle")["metadata"]["annotations"][
            "meta.helm.sh/release-name"
        ] = "wrong-release"
        self.write_live(live)
        self.write_client(client)
        self.write_stored(stored)
        self.write_server(server)

        result = self.run_script("--apply")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("server dry-run would change protected", result.stderr)
        self.assertEqual(self.applied_upgrade_lines(), [])
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")

    def test_server_cannot_omit_live_only_helm_or_controller_metadata(
        self,
    ) -> None:
        cases = (
            ("labels", "app.kubernetes.io/managed-by"),
            ("annotations", "meta.helm.sh/release-name"),
            ("annotations", "meta.helm.sh/release-namespace"),
            ("annotations", "deployment.kubernetes.io/revision"),
        )
        for section, key in cases:
            with self.subTest(section=section, key=key):
                live, client, stored, server = (
                    self.live_only_ownership_resources()
                )
                self.deployment_resource(server, "oracle")["metadata"][section].pop(
                    key
                )
                self.write_live(live)
                self.write_client(client)
                self.write_stored(stored)
                self.write_server(server)
                self.revision_path.write_text("21", encoding="utf-8")

                result = self.run_script("--apply")

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("server dry-run would change protected", result.stderr)
                self.assertEqual(self.applied_upgrade_lines(), [])
                self.assertEqual(
                    self.revision_path.read_text(encoding="utf-8"), "21"
                )

    def test_changed_old_to_new_metadata_blocks_before_helm(self) -> None:
        stored = resources()
        self.remove_helm_ownership_metadata(stored)
        self.write_stored(stored)

        result = self.run_script("--apply")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsupported old-to-new change", result.stderr)
        self.assertEqual(self.applied_upgrade_lines(), [])
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")

    def test_client_explicit_value_that_differs_from_live_is_rejected(self) -> None:
        client = resources()
        self.component_container(client, "oracle")["resources"]["limits"][
            "memory"
        ] = "3000Mi"
        self.write_client(client)

        result = self.run_script("--apply")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("protected resource spec", result.stderr)
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_stored_manifest_changed_resource_identity_blocks_before_apply(
        self,
    ) -> None:
        stored = resources()
        guardian = self.deployment_resource(stored, "guardian")
        guardian["metadata"]["name"] = "guardian-old"
        self.write_stored(stored)

        result = self.run_script("--apply")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("returned an unauthorized resource", result.stderr)
        self.assertEqual(self.applied_upgrade_lines(), [])
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")

    def test_stored_secret_manifest_is_discarded_without_raw_output(self) -> None:
        secret_sentinel = "stored-secret-payload-must-not-appear"
        self.stored_manifest_path.write_text(
            "---\napiVersion: v1\nkind: Secret\nmetadata:\n"
            "  name: forbidden-stored-secret\nstringData:\n"
            f"  payload: {secret_sentinel}\n"
            "---\n# stored-release-manifest\napiVersion: apps/v1\n"
            "kind: Deployment\nmetadata:\n  name: oracle\n",
            encoding="utf-8",
        )

        result = self.run_script()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("action=planned", result.stdout)
        self.assertNotIn(secret_sentinel, result.stdout + result.stderr)
        self.assertNotIn("forbidden-stored-secret", result.stdout + result.stderr)
        self.assertEqual(self.applied_upgrade_lines(), [])
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")

    def test_unrelated_stored_document_is_discarded_without_raw_output(self) -> None:
        unrelated_sentinel = "stored-unrelated-payload-must-not-appear"
        self.stored_manifest_path.write_text(
            "---\napiVersion: v1\nkind: ConfigMap\nmetadata:\n"
            "  name: ignored-stored-config\ndata:\n"
            f"  payload: {unrelated_sentinel}\n"
            "---\n# stored-release-manifest\napiVersion: apps/v1\n"
            "kind: Deployment\nmetadata:\n  name: oracle\n",
            encoding="utf-8",
        )

        result = self.run_script()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("action=planned", result.stdout)
        self.assertNotIn(unrelated_sentinel, result.stdout + result.stderr)
        self.assertNotIn("ignored-stored-config", result.stdout + result.stderr)
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_unrelated_protected_kind_is_discarded_without_raw_output(self) -> None:
        unrelated_sentinel = "stored-deployment-payload-must-not-appear"
        self.stored_manifest_path.write_text(
            "---\napiVersion: apps/v1\nkind: Deployment\nmetadata:\n"
            "  name: unrelated-deployment\nspec:\n"
            f"  ignored: {unrelated_sentinel}\n"
            "---\n# stored-release-manifest\napiVersion: apps/v1\n"
            "kind: Deployment\nmetadata:\n  name: oracle\n",
            encoding="utf-8",
        )

        result = self.run_script()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("action=planned", result.stdout)
        self.assertNotIn(unrelated_sentinel, result.stdout + result.stderr)
        self.assertNotIn("unrelated-deployment", result.stdout + result.stderr)
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_protected_kind_without_metadata_name_fails_closed(self) -> None:
        self.stored_manifest_path.write_text(
            "---\napiVersion: apps/v1\nkind: Deployment\nmetadata:\n"
            "  labels:\n    app: oracle\nspec:\n  replicas: 1\n",
            encoding="utf-8",
        )

        result = self.run_script("--apply")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stored Helm manifest resource identity is unsafe", result.stderr)
        self.assertEqual(self.applied_upgrade_lines(), [])
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")

    def test_sensitive_field_before_stored_kind_fails_without_raw_output(self) -> None:
        secret_sentinel = "pre-kind-secret-payload-must-not-appear"
        self.stored_manifest_path.write_text(
            f"stringData:\n  payload: {secret_sentinel}\nkind: Secret\n",
            encoding="utf-8",
        )

        result = self.run_script("--apply")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stored Helm manifest kind header is unsafe", result.stderr)
        self.assertNotIn(secret_sentinel, result.stdout + result.stderr)
        self.assertEqual(self.applied_upgrade_lines(), [])
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")

    def test_server_accepts_35_entry_order_only_rotation_and_allowed_labels(
        self,
    ) -> None:
        live, client, server = self.legacy_guardian_resources()
        gateway_environment = self.component_environment(live, "gateway")
        while len(gateway_environment) < 35:
            index = len(gateway_environment)
            gateway_environment.append(
                {"name": f"ORDER_FIXTURE_{index:02d}", "value": str(index)}
            )
        client = copy.deepcopy(live)
        server = copy.deepcopy(live)
        server_environment = self.component_environment(server, "gateway")
        server_environment[:] = server_environment[17:] + server_environment[:17]
        server_guardian = self.deployment_resource(server, "guardian")
        server_guardian["metadata"]["labels"].update(
            {"app": "guardian", "chain": "solana"}
        )
        self.assertEqual(len(gateway_environment), 35)
        self.write_live(live)
        self.write_client(client)
        self.write_server(server)
        self.write_stored(copy.deepcopy(client))

        result = self.run_script()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("action=planned", result.stdout)
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_duplicate_environment_name_is_rejected_before_helm_mutation(
        self,
    ) -> None:
        server = resources()
        environment = self.component_environment(server, "gateway")
        environment.append(copy.deepcopy(environment[0]))
        self.write_server(server)

        result = self.run_script("--apply")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("environment contains a duplicate name", result.stderr)
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_order_sensitive_environment_literal_is_rejected_before_mutation(
        self,
    ) -> None:
        live = resources()
        self.component_environment(live, "gateway").append(
            {"name": "ORDER_SENSITIVE", "value": "prefix-$(NETWORK_ID)"}
        )
        self.write_live(live)
        self.write_rendered(copy.deepcopy(live))
        self.write_stored(copy.deepcopy(live))

        result = self.run_script("--apply")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("order-sensitive literal", result.stderr)
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_altered_server_environment_entry_is_rejected(self) -> None:
        server = resources()
        environment = self.component_environment(server, "gateway")
        next(item for item in environment if item["name"] == "NETWORK_ID")[
            "value"
        ] = "other-network"
        self.write_server(server)

        result = self.run_script("--apply")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "Kubernetes server dry-run would change a protected resource spec",
            result.stderr,
        )
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_unexpected_server_label_is_rejected(self) -> None:
        server = resources()
        guardian = self.deployment_resource(server, "guardian")
        guardian["metadata"]["labels"]["unexpected"] = "value"
        self.write_server(server)

        result = self.run_script("--apply")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("would change protected resource metadata", result.stderr)
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_allowed_server_label_with_wrong_value_is_rejected(self) -> None:
        live, client, server = self.legacy_guardian_resources()
        guardian = self.deployment_resource(server, "guardian")
        guardian["metadata"]["labels"]["app"] = "wrong"
        self.write_live(live)
        self.write_client(client)
        self.write_server(server)
        self.write_stored(copy.deepcopy(client))

        result = self.run_script("--apply")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("added an invalid Deployment label", result.stderr)
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_server_label_at_unexpected_path_is_rejected(self) -> None:
        server = resources()
        service_value = next(
            item
            for item in server
            if item["kind"] == "Service" and item["metadata"]["name"] == "guardian"
        )
        service_value["metadata"]["labels"]["chain"] = "solana"
        self.write_server(server)

        result = self.run_script("--apply")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("would change protected resource metadata", result.stderr)
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_client_live_mismatch_blocks_before_server_dry_run(self) -> None:
        client = resources()
        environment = self.component_environment(client, "gateway")
        next(item for item in environment if item["name"] == "NETWORK_ID")[
            "value"
        ] = "other-network"
        self.write_client(client)

        result = self.run_script("--apply")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "Helm client manifest would change a protected resource spec",
            result.stderr,
        )
        self.assertFalse(
            any("--dry-run=server" in line for line in self.kubectl_log.read_text().splitlines())
        )
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_guardian_zero_null_and_empty_endpoints_are_equivalent(self) -> None:
        endpoint_hashes = []
        for endpoint_value in (None, []):
            guardian_slice = endpoint_slice("guardian")
            guardian_slice["endpoints"] = endpoint_value
            self.write_endpoint_slices("guardian", [guardian_slice])
            result = self.run_script()
            self.assertEqual(result.returncode, 0, result.stderr)
            endpoint_hashes.append(
                next(
                    line
                    for line in result.stdout.splitlines()
                    if line.startswith("endpointsStable=true hash=")
                )
            )
        self.assertEqual(endpoint_hashes[0], endpoint_hashes[1])
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_malformed_endpoints_fail_before_helm_and_never_apply(self) -> None:
        for malformed_endpoints in ("invalid", {"unexpected": "object"}):
            with self.subTest(malformed_endpoints=malformed_endpoints):
                guardian_slice = endpoint_slice("guardian")
                guardian_slice["endpoints"] = malformed_endpoints
                self.write_endpoint_slices("guardian", [guardian_slice])
                result = self.run_script("--apply")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(
                    "EndpointSlice endpoints is missing or invalid", result.stderr
                )
                self.assertEqual(self.helm_lines(), ["upgrade --help"])
                self.assertEqual(self.applied_upgrade_lines(), [])
                self.assertEqual(
                    self.revision_path.read_text(encoding="utf-8"), "21"
                )
                self.helm_log.unlink()

    def test_apply_records_one_revision_without_workload_changes(self) -> None:
        result = self.run_script("--apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "22")
        self.assertIn("baselineHelmRevision=22", result.stdout)
        self.assertIn("rollbackRevision=22", result.stdout)
        self.assertIn("postApplyPodUidsRestartsReadinessUnchanged=true", result.stdout)
        self.assertIn("postApplyResourceVersionsUnchanged=true", result.stdout)
        self.assertEqual(len(self.applied_upgrade_lines()), 1)
        self.assertEqual(len(self.dry_run_upgrade_lines()), 1)
        self.assertIn("--history-max 0", self.applied_upgrade_lines()[0])
        self.assertIn("--history-max 0", self.dry_run_upgrade_lines()[0])
        all_commands = self.helm_lines() + self.kubectl_log.read_text(
            encoding="utf-8"
        ).splitlines()
        self.assertFalse(
            any("delete" in command.split() for command in all_commands)
        )

    def test_exclusive_window_assertion_is_required_before_tool_use(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                str(self.script_dir / SCRIPT.name),
                "--network",
                "devnet",
                "--host-id",
                "stra01",
                "--expected-current-oracle-image",
                ORACLE_IMAGE,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=self.environment,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--coordinator-exclusive-window-confirmed", result.stderr)
        self.assertFalse(self.kubectl_log.exists())
        self.assertFalse(self.helm_log.exists())

    def test_host_local_lock_contention_blocks_before_tool_use(self) -> None:
        descriptor = os.open(
            LOCK_FILE,
            os.O_RDWR | os.O_CREAT | os.O_CLOEXEC | os.O_NOFOLLOW,
            0o600,
        )
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_script("--apply")
        finally:
            fcntl.flock(descriptor, fcntl.LOCK_UN)
            os.close(descriptor)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("holds the lock", result.stderr)
        self.assertFalse(self.kubectl_log.exists())
        self.assertFalse(self.helm_log.exists())

    def test_oracle_zero_is_rejected_before_helm_render_or_mutation(self) -> None:
        zero = resources(oracle_replicas=0)
        self.write_live(zero)
        self.write_rendered(zero)
        result = self.run_script("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Oracle replicas=0", result.stderr)
        self.assertFalse(
            any(
                line.startswith("upgrade sb-oracle-devnet")
                for line in self.helm_lines()
            )
        )
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")

    def test_mutable_auxiliary_image_is_rejected(self) -> None:
        mutable = resources(guardian_image="docker.io/switchboardlabs/guardian:latest")
        self.write_live(mutable)
        self.write_rendered(mutable)
        result = self.run_script("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not pinned", result.stderr)
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")

    def test_server_dry_run_spec_drift_blocks_helm_mutation(self) -> None:
        rendered = resources()
        next(
            item
            for item in rendered
            if item["kind"] == "Deployment" and item["metadata"]["name"] == "gateway"
        )["spec"]["template"]["spec"]["containers"][0]["resources"]["limits"]["memory"] = "3000Mi"
        self.write_server(rendered)
        result = self.run_script("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("protected resource spec", result.stderr)
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_live_drift_after_dry_run_blocks_helm_mutation(self) -> None:
        self.environment["DRIFT_ON_SECOND_GET"] = "1"
        result = self.run_script("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("live state drifted", result.stderr)
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_missing_apply_permission_blocks_helm_mutation(self) -> None:
        self.environment["CAN_I"] = "no"
        result = self.run_script("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("lacks a required baseline permission", result.stderr)
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")
        self.assertEqual(self.applied_upgrade_lines(), [])

    def test_post_helm_resource_version_drift_fails_closed(self) -> None:
        self.environment["POST_HELM_RESOURCE_VERSION_DRIFT"] = "1"
        result = self.run_script("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("resourceVersion changed", result.stderr)
        self.assertIn("requires-secret-safe-Helm-revision-readback", result.stderr)
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "22")
        self.assertEqual(len(self.applied_upgrade_lines()), 1)

    def test_default_mode_rejects_post_helm_generation_advance(self) -> None:
        self.environment["POST_HELM_MUTATION"] = "oracle-generation"
        result = self.run_script("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Deployment generation changed", result.stderr)
        self.assertIn("requires-secret-safe-Helm-revision-readback", result.stderr)
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "22")
        self.assertEqual(len(self.applied_upgrade_lines()), 1)

    def test_partial_confidential_policy_state_is_rejected_without_leakage(self) -> None:
        partial = resources(
            policies={
                "oracle": POLICY_SENTINEL,
                "guardian": None,
                "gateway": None,
            }
        )
        self.write_live(partial)
        self.write_rendered(partial)
        result = self.run_script("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("all components or none", result.stderr)
        self.assertNotIn(POLICY_SENTINEL, result.stdout + result.stderr)
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")

    def test_complete_confidential_policy_state_is_preserved_without_output(self) -> None:
        complete = resources(
            policies={component: f"{POLICY_SENTINEL}-{component}" for component in COMPONENTS}
        )
        self.write_live(complete)
        self.write_rendered(complete)
        self.write_stored(copy.deepcopy(complete))
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("action=planned", result.stdout)
        self.assertNotIn(POLICY_SENTINEL, result.stdout + result.stderr)

    def test_operator_confirmed_oracle_image_must_match(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                str(self.script_dir / SCRIPT.name),
                "--network",
                "devnet",
                "--host-id",
                "stra01",
                "--expected-current-oracle-image",
                f"docker.io/switchboardlabs/oracle@sha256:{'d' * 64}",
                "--coordinator-exclusive-window-confirmed",
                "--apply",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=self.environment,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("operator-confirmed", result.stderr)
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")

    def test_secret_manifest_is_rejected_without_printing_manifest(self) -> None:
        self.environment["HELM_RENDER_SECRET"] = "1"
        result = self.run_script("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unexpectedly contained a Secret", result.stderr)
        self.assertNotIn("forbidden", result.stdout + result.stderr)
        self.assertEqual(self.revision_path.read_text(encoding="utf-8"), "21")

    def test_mainnet_and_unknown_hosts_are_rejected_without_tool_use(self) -> None:
        for network, host_id in (("mainnet", "stra01"), ("devnet", "lim05"), ("devnet", "eri")):
            result = subprocess.run(
                [
                    sys.executable,
                    str(self.script_dir / SCRIPT.name),
                    "--network",
                    network,
                    "--host-id",
                    host_id,
                    "--expected-current-oracle-image",
                    ORACLE_IMAGE,
                    "--coordinator-exclusive-window-confirmed",
                    "--apply",
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=self.environment,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.kubectl_log.exists())
        self.assertFalse(self.helm_log.exists())


if __name__ == "__main__":
    unittest.main()
