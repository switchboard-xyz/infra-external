#!/usr/bin/env python3

from __future__ import annotations

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
COMPONENTS = ("oracle", "guardian", "gateway")
ORACLE_IMAGE = f"docker.io/switchboardlabs/oracle@sha256:{'a' * 64}"
GUARDIAN_IMAGE = f"docker.io/switchboardlabs/guardian@sha256:{'b' * 64}"
GATEWAY_IMAGE = f"docker.io/switchboardlabs/gateway@sha256:{'c' * 64}"
PAYER_KEY = "payer-key-must-not-appear"
SUI_NAME = "sui-name-must-not-appear"
SUI_KEY = "sui-key-must-not-appear"
POLICY_SENTINEL = "policy-must-not-appear"
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
    return {
        "apiVersion": "apps/v1",
        "kind": "Deployment",
        "metadata": owned_metadata(component, resource_version),
        "spec": {
            "replicas": replicas,
            "selector": {"matchLabels": {"app": component}},
            "strategy": {
                "rollingUpdate": {"maxSurge": 1, "maxUnavailable": 0},
                "type": "RollingUpdate",
            },
            "template": {
                "metadata": {
                    "labels": {"app": component, "cluster": "devnet"},
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
        self.rendered_path = self.root / "rendered.json"
        self.nodes_path = self.root / "nodes.json"
        self.revision_path = self.root / "revision"
        self.deployment_get_count = self.root / "deployment-get-count"
        self.pod_dir = self.root / "pods"
        self.endpoint_dir = self.root / "endpoints"
        self.pod_dir.mkdir()
        self.endpoint_dir.mkdir()

        baseline_resources = resources()
        self.live_path.write_text(json.dumps(baseline_resources), encoding="utf-8")
        self.rendered_path.write_text(
            json.dumps(baseline_resources), encoding="utf-8"
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
    print("--dry-run must be server --server-side")
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

if "apply" in args and "--dry-run=server" in args:
    sys.stdin.read()
    items = json.loads(Path(os.environ["RENDERED_PATH"]).read_text(encoding="utf-8"))
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

if args == ["upgrade", "--help"]:
    print("--dry-run client server --hide-secret --history-max --reuse-values --no-hooks")
    raise SystemExit(0)
if args and args[0] == "list":
    revision = int(Path(os.environ["REVISION_PATH"]).read_text(encoding="utf-8"))
    print(json.dumps([{"name": "sb-oracle-devnet", "revision": revision, "status": "deployed"}]))
    raise SystemExit(0)
if args and args[0] == "upgrade" and "--dry-run=server" in args:
    if os.environ.get("HELM_RENDER_SECRET") == "1":
        print("MANIFEST:\n---\napiVersion: v1\nkind: Secret\nmetadata:\n  name: forbidden\n")
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
                "RENDERED_PATH": str(self.rendered_path),
                "REVISION_PATH": str(self.revision_path),
                "DEPLOYMENT_GET_COUNT": str(self.deployment_get_count),
                "POD_DIR": str(self.pod_dir),
                "ENDPOINT_DIR": str(self.endpoint_dir),
            }
        )

    def tearDown(self) -> None:
        self.temp_dir.cleanup()
        for path, expected in self.protected_hashes.items():
            self.assertEqual(file_hash(path), expected)

    def write_live(self, value: list[dict[str, object]]) -> None:
        self.live_path.write_text(json.dumps(value), encoding="utf-8")

    def write_rendered(self, value: list[dict[str, object]]) -> None:
        self.rendered_path.write_text(json.dumps(value), encoding="utf-8")

    def run_script(self, *extra: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(self.script_dir / SCRIPT.name),
                "--network",
                "devnet",
                "--host-id",
                "stra01",
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
            and "--dry-run=server" not in line
        ]

    def dry_run_upgrade_lines(self) -> list[str]:
        return [
            line
            for line in self.helm_lines()
            if line.startswith("upgrade sb-oracle-devnet ")
            and "--dry-run=server" in line
        ]

    def test_guardian_zero_plan_is_secret_safe_and_non_mutating(self) -> None:
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("resourceSpecsEquivalent=true hash=", result.stdout)
        self.assertIn("podTemplatesEquivalent=true hash=", result.stdout)
        self.assertIn("secretReferencesEquivalent=true hash=", result.stdout)
        self.assertIn("activePodsStable=true hash=", result.stdout)
        self.assertIn("action=planned", result.stdout)
        self.assertEqual(self.applied_upgrade_lines(), [])
        combined = result.stdout + result.stderr
        for forbidden in (PAYER_KEY, SUI_NAME, SUI_KEY, POLICY_SENTINEL):
            self.assertNotIn(forbidden, combined)

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
        self.write_rendered(rendered)
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
        self.assertIn("unexpectedly rendered a Secret", result.stderr)
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
