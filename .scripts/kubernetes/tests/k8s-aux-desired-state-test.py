#!/usr/bin/env python3

from __future__ import annotations

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
SCRIPT = REPO_DIR / ".scripts/kubernetes/k8s-aux-desired-state.py"
DESIRED_STATE = REPO_DIR / ".scripts/kubernetes/desired-state"
DEVNET_NAMESPACE = "switchboard-oracle-devnet"
TEST_CONTEXT = "test-context"
NODE_NAMES = {
    "guardian": "ovh-stra-01",
    "gateway": "ovh-lim-05",
}
DESIRED_IMAGES = {
    "guardian": (
        "docker.io/switchboardlabs/guardian@"
        "sha256:3645615c8fe758b4f84813958af114e1492627bce4373490781073ce20da698d"
    ),
    "gateway": (
        "docker.io/switchboardlabs/gateway@"
        "sha256:d9f068b1b2b6558350ce2f3974b31d96ba7750f6ecc3988c914c848be068513a"
    ),
}
PROTECTED_REPOSITORY_FILES = [
    REPO_DIR / ".scripts/helm/charts/on-demand/values.yaml",
    REPO_DIR / ".scripts/helm/cfg/mainnet-solana-values.yaml",
    REPO_DIR / ".scripts/helm/charts/on-demand/templates/oracle.yaml",
    REPO_DIR / ".scripts/helm/charts/on-demand/templates/guardian.yaml",
    REPO_DIR / ".scripts/helm/charts/on-demand/templates/gateway.yaml",
    REPO_DIR / ".scripts/kubernetes/k8s-oracle-install.sh",
]


def file_digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pinned_image(component: str, fill: str) -> str:
    return f"docker.io/switchboardlabs/{component}@sha256:{fill * 64}"


def deployment(
    component: str,
    namespace: str,
    replicas: int,
    image: str,
    *,
    network: str = "devnet",
    resource_version: str = "17",
) -> dict[str, object]:
    return {
        "apiVersion": "apps/v1",
        "kind": "Deployment",
        "metadata": {
            "name": component,
            "namespace": namespace,
            "resourceVersion": resource_version,
            "labels": {"app": component},
        },
        "spec": {
            "replicas": replicas,
            "selector": {"matchLabels": {"app": component}},
            "template": {
                "metadata": {"labels": {"app": component}},
                "spec": {
                    "containers": [
                        {
                            "name": component,
                            "image": image,
                            "env": [
                                {"name": "CHAIN", "value": "solana"},
                                {"name": "NETWORK_ID", "value": network},
                            ],
                        }
                    ]
                },
            },
        },
    }


def node_list(*node_names: str) -> dict[str, object]:
    return {
        "apiVersion": "v1",
        "kind": "List",
        "items": [{"metadata": {"name": name}} for name in node_names],
    }


class AuxDesiredStateTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.protected_hashes = {
            path: file_digest(path) for path in PROTECTED_REPOSITORY_FILES
        }

    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory(
            prefix=".aux-desired-state-test-", dir=REPO_DIR
        )
        self.root = Path(self.temp_dir.name)
        self.script_dir = self.root / "kubernetes"
        self.script_dir.mkdir()
        shutil.copy2(SCRIPT, self.script_dir / SCRIPT.name)
        shutil.copytree(DESIRED_STATE, self.script_dir / "desired-state")

        self.bin_dir = self.root / "bin"
        self.bin_dir.mkdir()
        self.log = self.root / "kubectl.log"
        self.patch_log = self.root / "patches.jsonl"
        self.state = self.root / "deployment.json"
        self.nodes = self.root / "nodes.json"
        self.post_get_marker = self.root / "post-get-failed"
        mock = self.bin_dir / "kubectl"
        mock.write_text(
            r'''#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path


def fail(code=64):
    raise SystemExit(code)


def read_pointer(document, path):
    current = document
    for segment in path.removeprefix("/").split("/"):
        segment = segment.replace("~1", "/").replace("~0", "~")
        current = current[int(segment)] if isinstance(current, list) else current[segment]
    return current


def replace_pointer(document, path, value):
    segments = path.removeprefix("/").split("/")
    current = document
    for segment in segments[:-1]:
        segment = segment.replace("~1", "/").replace("~0", "~")
        current = current[int(segment)] if isinstance(current, list) else current[segment]
    final = segments[-1].replace("~1", "/").replace("~0", "~")
    if isinstance(current, list):
        current[int(final)] = value
    else:
        current[final] = value


arguments = sys.argv[1:]
with Path(os.environ["KUBECTL_LOG"]).open("a", encoding="utf-8") as stream:
    stream.write(" ".join(arguments) + "\n")

if arguments == ["config", "current-context"]:
    print(os.environ.get("KUBECTL_CONTEXT", ""))
    raise SystemExit(0)

context = os.environ["KUBECTL_CONTEXT"]
if arguments[:2] != ["--context", context]:
    fail(65)
arguments = arguments[2:]

if arguments == ["get", "nodes", "--output=json"]:
    print(Path(os.environ["KUBECTL_NODES"]).read_text(encoding="utf-8"))
    raise SystemExit(0)

if (
    len(arguments) == 6
    and arguments[0] == "--namespace"
    and arguments[2:5] == ["get", "deployment", os.environ["KUBECTL_COMPONENT"]]
    and arguments[5] == "--output=json"
):
    patch_log = Path(os.environ["KUBECTL_PATCH_LOG"])
    marker = Path(os.environ["KUBECTL_POST_GET_MARKER"])
    if (
        os.environ.get("KUBECTL_FAIL_FIRST_POST_PATCH_GET") == "1"
        and patch_log.exists()
        and not marker.exists()
    ):
        marker.touch()
        fail(70)
    print(Path(os.environ["KUBECTL_STATE"]).read_text(encoding="utf-8"))
    raise SystemExit(0)

if arguments[:3] == ["auth", "can-i", "patch"]:
    print(os.environ.get("KUBECTL_CAN_PATCH", "yes"))
    raise SystemExit(0)

if (
    len(arguments) >= 9
    and arguments[0] == "--namespace"
    and arguments[2:5] == ["patch", "deployment", os.environ["KUBECTL_COMPONENT"]]
):
    patch_log = Path(os.environ["KUBECTL_PATCH_LOG"])
    patch_count = (
        len(patch_log.read_text(encoding="utf-8").splitlines())
        if patch_log.exists()
        else 0
    )
    if patch_count > 0 and os.environ.get("KUBECTL_ROLLBACK_FAIL") == "1":
        fail(71)

    patch = json.loads(arguments[arguments.index("--patch") + 1])
    state_path = Path(os.environ["KUBECTL_STATE"])
    state = json.loads(state_path.read_text(encoding="utf-8"))
    if (
        patch_count == 0
        and os.environ.get("KUBECTL_RACE_TO_DESIRED_BEFORE_FORWARD") == "1"
    ):
        desired_replace = next(
            operation for operation in patch if operation["op"] == "replace"
        )
        replace_pointer(state, desired_replace["path"], desired_replace["value"])
        metadata = state["metadata"]
        metadata["resourceVersion"] = str(int(metadata["resourceVersion"]) + 1)
        state_path.write_text(json.dumps(state), encoding="utf-8")
    for operation in patch:
        if operation["op"] == "test":
            if read_pointer(state, operation["path"]) != operation["value"]:
                fail(72)
        elif operation["op"] == "replace":
            replace_pointer(state, operation["path"], operation["value"])
        else:
            fail(73)
    metadata = state["metadata"]
    metadata["resourceVersion"] = str(int(metadata["resourceVersion"]) + 1)
    state_path.write_text(json.dumps(state), encoding="utf-8")
    with patch_log.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(patch) + "\n")
    if (
        patch_count == 0
        and os.environ.get("KUBECTL_UNCONFIRMED_FORWARD_RESPONSE") == "1"
    ):
        print("{")
        raise SystemExit(0)
    print(json.dumps(state))
    raise SystemExit(0)

fail()
''',
            encoding="utf-8",
        )
        mock.chmod(0o755)

    def tearDown(self) -> None:
        self.assert_repository_files_unchanged()
        self.temp_dir.cleanup()

    def assert_repository_files_unchanged(self) -> None:
        for path, expected in self.protected_hashes.items():
            self.assertEqual(file_digest(path), expected, path)

    def write_live_state(self, live: dict[str, object]) -> None:
        self.state.write_text(json.dumps(live), encoding="utf-8")
        component = live["metadata"]["name"]
        self.component = component
        self.nodes.write_text(
            json.dumps(node_list(NODE_NAMES[component])), encoding="utf-8"
        )

    def run_script(
        self,
        *arguments: str,
        expect_kubectl: bool = True,
        extra_env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env.update(
            {
                "PATH": f"{self.bin_dir}:{env['PATH']}",
                "KUBECTL_LOG": str(self.log),
                "KUBECTL_PATCH_LOG": str(self.patch_log),
                "KUBECTL_STATE": str(self.state),
                "KUBECTL_NODES": str(self.nodes),
                "KUBECTL_POST_GET_MARKER": str(self.post_get_marker),
                "KUBECTL_CONTEXT": TEST_CONTEXT,
                "KUBECTL_COMPONENT": getattr(self, "component", "missing"),
            }
        )
        env.update(extra_env or {})
        result = subprocess.run(
            [sys.executable, str(self.script_dir / SCRIPT.name), *arguments],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
            check=False,
        )
        if not expect_kubectl:
            self.assertFalse(
                self.log.exists(), self.log.read_text() if self.log.exists() else ""
            )
        return result

    def kubectl_lines(self) -> list[str]:
        return self.log.read_text(encoding="utf-8").splitlines()

    def patches(self) -> list[list[dict[str, object]]]:
        if not self.patch_log.exists():
            return []
        return [
            json.loads(line)
            for line in self.patch_log.read_text(encoding="utf-8").splitlines()
        ]

    def assert_context_is_fixed_after_selection(self) -> None:
        lines = self.kubectl_lines()
        self.assertEqual(lines[0], "config current-context")
        self.assertTrue(
            all(line.startswith(f"--context {TEST_CONTEXT} ") for line in lines[1:]),
            lines,
        )

    def test_exact_devnet_targets_are_checked_in(self) -> None:
        overlays = self.script_dir / "desired-state/devnet"
        self.assertEqual({path.name for path in overlays.iterdir()}, {"stra01.json", "lim05.json"})
        self.assertEqual(
            json.loads((overlays / "stra01.json").read_text(encoding="utf-8")),
            {
                "applyEnabled": True,
                "component": "guardian",
                "hostId": "stra01",
                "image": "docker.io/switchboardlabs/guardian",
                "imageDigest": DESIRED_IMAGES["guardian"].split("@", 1)[1],
                "network": "devnet",
                "namespace": DEVNET_NAMESPACE,
                "nodeName": "ovh-stra-01",
                "replicas": 0,
            },
        )
        self.assertEqual(
            json.loads((overlays / "lim05.json").read_text(encoding="utf-8")),
            {
                "applyEnabled": False,
                "component": "gateway",
                "hostId": "lim05",
                "image": "docker.io/switchboardlabs/gateway",
                "imageDigest": DESIRED_IMAGES["gateway"].split("@", 1)[1],
                "network": "devnet",
                "namespace": DEVNET_NAMESPACE,
                "nodeName": "ovh-lim-05",
                "replicas": 1,
            },
        )
        self.assertFalse((self.script_dir / "desired-state/mainnet").exists())

    def test_mainnet_is_rejected_before_kubectl(self) -> None:
        result = self.run_script(
            "--network",
            "mainnet",
            "--host-id",
            "lim05",
            "--apply",
            expect_kubectl=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("devnet-only", result.stderr)

    def test_unknown_hosts_are_rejected_before_kubectl(self) -> None:
        for host_id in ("eri", "rbx01"):
            with self.subTest(host_id=host_id):
                result = self.run_script(
                    "--network",
                    "devnet",
                    "--host-id",
                    host_id,
                    "--apply",
                    expect_kubectl=False,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("unknown devnet host ID", result.stderr)

    def test_malformed_host_id_is_rejected_before_kubectl(self) -> None:
        result = self.run_script(
            "--network",
            "devnet",
            "--host-id",
            "../mainnet",
            "--apply",
            expect_kubectl=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("host ID is invalid", result.stderr)

    def test_known_host_requires_its_checked_in_overlay_before_kubectl(self) -> None:
        (self.script_dir / "desired-state/devnet/stra01.json").unlink()
        result = self.run_script(
            "--network",
            "devnet",
            "--host-id",
            "stra01",
            "--apply",
            expect_kubectl=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("overlay is missing", result.stderr)

    def test_malformed_digest_is_rejected_before_kubectl(self) -> None:
        overlay = self.script_dir / "desired-state/devnet/stra01.json"
        data = json.loads(overlay.read_text(encoding="utf-8"))
        data["imageDigest"] = "latest"
        overlay.write_text(json.dumps(data), encoding="utf-8")
        result = self.run_script(
            "--network",
            "devnet",
            "--host-id",
            "stra01",
            "--apply",
            expect_kubectl=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not immutable", result.stderr)

    def test_overlay_network_mismatch_is_rejected_before_kubectl(self) -> None:
        overlay = self.script_dir / "desired-state/devnet/stra01.json"
        data = json.loads(overlay.read_text(encoding="utf-8"))
        data["network"] = "mainnet"
        overlay.write_text(json.dumps(data), encoding="utf-8")
        result = self.run_script(
            "--network",
            "devnet",
            "--host-id",
            "stra01",
            "--apply",
            expect_kubectl=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("network does not match", result.stderr)

    def test_overlay_namespace_mismatch_is_rejected_before_kubectl(self) -> None:
        overlay = self.script_dir / "desired-state/devnet/stra01.json"
        data = json.loads(overlay.read_text(encoding="utf-8"))
        data["namespace"] = "switchboard-oracle-mainnet"
        overlay.write_text(json.dumps(data), encoding="utf-8")
        result = self.run_script(
            "--network",
            "devnet",
            "--host-id",
            "stra01",
            "--apply",
            expect_kubectl=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not the exact devnet namespace", result.stderr)

    def test_overlay_cannot_redirect_an_authorized_host_before_kubectl(self) -> None:
        overlay = self.script_dir / "desired-state/devnet/stra01.json"
        data = json.loads(overlay.read_text(encoding="utf-8"))
        data["nodeName"] = "ovh-lim-05"
        overlay.write_text(json.dumps(data), encoding="utf-8")
        result = self.run_script(
            "--network",
            "devnet",
            "--host-id",
            "stra01",
            "--apply",
            expect_kubectl=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match the authorized host", result.stderr)

    def test_namespace_cannot_be_supplied_by_the_operator(self) -> None:
        result = self.run_script(
            "--network",
            "devnet",
            "--host-id",
            "stra01",
            "--namespace",
            "switchboard-oracle-mainnet",
            expect_kubectl=False,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("unrecognized arguments", result.stderr)

    def test_wrong_single_node_context_is_rejected_before_deployment_read(self) -> None:
        self.write_live_state(
            deployment("gateway", DEVNET_NAMESPACE, 1, pinned_image("gateway", "a"))
        )
        self.nodes.write_text(json.dumps(node_list("ovh-stra-01")), encoding="utf-8")
        result = self.run_script("--network", "devnet", "--host-id", "lim05", "--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match desired-state host identity", result.stderr)
        self.assertEqual(
            self.kubectl_lines(),
            [
                "config current-context",
                f"--context {TEST_CONTEXT} get nodes --output=json",
            ],
        )

    def test_multi_node_context_is_rejected_before_deployment_read(self) -> None:
        self.write_live_state(
            deployment("guardian", DEVNET_NAMESPACE, 0, pinned_image("guardian", "a"))
        )
        self.nodes.write_text(
            json.dumps(node_list("ovh-stra-01", "another-node")), encoding="utf-8"
        )
        result = self.run_script("--network", "devnet", "--host-id", "stra01")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("exactly one Kubernetes node", result.stderr)
        self.assertEqual(len(self.kubectl_lines()), 2)

    def test_live_network_mismatch_is_rejected_without_mutation(self) -> None:
        self.write_live_state(
            deployment(
                "gateway",
                DEVNET_NAMESPACE,
                1,
                pinned_image("gateway", "a"),
                network="mainnet",
            )
        )
        result = self.run_script("--network", "devnet", "--host-id", "lim05", "--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("network does not match", result.stderr)
        self.assertEqual(len(self.kubectl_lines()), 3)
        self.assertEqual(self.patches(), [])

    def test_replica_mismatch_is_rejected_without_scaling(self) -> None:
        self.write_live_state(
            deployment("guardian", DEVNET_NAMESPACE, 1, pinned_image("guardian", "a"))
        )
        result = self.run_script("--network", "devnet", "--host-id", "stra01", "--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("refusing to scale implicitly", result.stderr)
        self.assertEqual(len(self.kubectl_lines()), 3)
        self.assertEqual(self.patches(), [])

    def test_plan_is_read_only_and_uses_the_exact_context_and_namespace(self) -> None:
        self.write_live_state(
            deployment("gateway", DEVNET_NAMESPACE, 1, pinned_image("gateway", "a"))
        )
        result = self.run_script("--network", "devnet", "--host-id", "lim05")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("action=planned", result.stdout)
        self.assertIn(f"namespace={DEVNET_NAMESPACE}", result.stdout)
        self.assertEqual(len(self.kubectl_lines()), 3)
        self.assert_context_is_fixed_after_selection()
        self.assertIn(
            f"--namespace {DEVNET_NAMESPACE} get deployment gateway",
            self.kubectl_lines()[2],
        )
        self.assertEqual(self.patches(), [])

    def test_lim05_apply_is_disabled_before_rbac_or_patch(self) -> None:
        current = pinned_image("gateway", "a")
        self.write_live_state(deployment("gateway", DEVNET_NAMESPACE, 1, current))
        result = self.run_script(
            "--network",
            "devnet",
            "--host-id",
            "lim05",
            "--expected-current-image",
            current,
            "--apply",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("apply is disabled", result.stderr)
        self.assertEqual(len(self.kubectl_lines()), 3)
        self.assertEqual(self.patches(), [])

    def test_future_running_apply_rejects_a_mutable_rollback_image(self) -> None:
        overlay = self.script_dir / "desired-state/devnet/lim05.json"
        data = json.loads(overlay.read_text(encoding="utf-8"))
        data["applyEnabled"] = True
        overlay.write_text(json.dumps(data), encoding="utf-8")
        current = "docker.io/switchboardlabs/gateway:devnet"
        self.write_live_state(deployment("gateway", DEVNET_NAMESPACE, 1, current))
        result = self.run_script(
            "--network",
            "devnet",
            "--host-id",
            "lim05",
            "--expected-current-image",
            current,
            "--apply",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires an immutable current rollback image", result.stderr)
        self.assertEqual(len(self.kubectl_lines()), 3)
        self.assertEqual(self.patches(), [])

    def test_apply_requires_the_planned_current_image(self) -> None:
        current = "docker.io/switchboardlabs/guardian:devnet"
        self.write_live_state(deployment("guardian", DEVNET_NAMESPACE, 0, current))
        result = self.run_script(
            "--network", "devnet", "--host-id", "stra01", "--apply"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expected-current-image is required", result.stderr)
        self.assertEqual(len(self.kubectl_lines()), 3)

    def test_apply_rejects_a_stale_planned_current_image(self) -> None:
        current = "docker.io/switchboardlabs/guardian:devnet"
        self.write_live_state(deployment("guardian", DEVNET_NAMESPACE, 0, current))
        result = self.run_script(
            "--network",
            "devnet",
            "--host-id",
            "stra01",
            "--expected-current-image",
            pinned_image("guardian", "b"),
            "--apply",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("operator-confirmed current image", result.stderr)
        self.assertEqual(len(self.kubectl_lines()), 3)

    def test_apply_requires_patch_permission_without_attempting_mutation(self) -> None:
        current = "docker.io/switchboardlabs/guardian:devnet"
        self.write_live_state(deployment("guardian", DEVNET_NAMESPACE, 0, current))
        result = self.run_script(
            "--network",
            "devnet",
            "--host-id",
            "stra01",
            "--expected-current-image",
            current,
            "--apply",
            extra_env={"KUBECTL_CAN_PATCH": "no"},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot patch", result.stderr)
        self.assertEqual(len(self.kubectl_lines()), 4)
        self.assertEqual(self.patches(), [])

    def test_already_reconciled_target_is_a_read_only_noop(self) -> None:
        self.write_live_state(
            deployment("gateway", DEVNET_NAMESPACE, 1, DESIRED_IMAGES["gateway"])
        )
        result = self.run_script("--network", "devnet", "--host-id", "lim05", "--apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("action=noop", result.stdout)
        self.assertEqual(len(self.kubectl_lines()), 3)
        self.assertEqual(self.patches(), [])

    def test_conflicting_metadata_app_label_is_rejected_before_mutation(self) -> None:
        current = "docker.io/switchboardlabs/guardian:devnet"
        live = deployment("guardian", DEVNET_NAMESPACE, 0, current)
        live["metadata"]["labels"]["app"] = "oracle"
        self.write_live_state(live)

        result = self.run_script(
            "--network",
            "devnet",
            "--host-id",
            "stra01",
            "--expected-current-image",
            current,
            "--apply",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("labels do not match", result.stderr)
        self.assertEqual(len(self.kubectl_lines()), 3)
        self.assertEqual(self.patches(), [])
        self.assertEqual(json.loads(self.state.read_text(encoding="utf-8")), live)

    def test_stra01_absent_metadata_app_label_patches_only_image(self) -> None:
        current = "docker.io/switchboardlabs/guardian:devnet"
        live = deployment("guardian", DEVNET_NAMESPACE, 0, current)
        del live["metadata"]["labels"]["app"]
        self.write_live_state(live)

        result = self.run_script(
            "--network",
            "devnet",
            "--host-id",
            "stra01",
            "--expected-current-image",
            current,
            "--apply",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("action=applied", result.stdout)
        patch = self.patches()[0]
        self.assertNotIn(
            "/metadata/labels/app", [operation["path"] for operation in patch]
        )
        self.assertEqual(
            [operation for operation in patch if operation["op"] == "replace"],
            [
                {
                    "op": "replace",
                    "path": "/spec/template/spec/containers/0/image",
                    "value": DESIRED_IMAGES["guardian"],
                }
            ],
        )

        actual = json.loads(self.state.read_text(encoding="utf-8"))
        expected = json.loads(json.dumps(live))
        expected["metadata"]["resourceVersion"] = "18"
        expected["spec"]["template"]["spec"]["containers"][0]["image"] = (
            DESIRED_IMAGES["guardian"]
        )
        self.assertEqual(actual, expected)

    def test_stra01_matching_metadata_app_label_patches_only_selected_image(self) -> None:
        current = "docker.io/switchboardlabs/guardian:devnet"
        self.write_live_state(deployment("guardian", DEVNET_NAMESPACE, 0, current))
        result = self.run_script(
            "--network",
            "devnet",
            "--host-id",
            "stra01",
            "--expected-current-image",
            current,
            "--apply",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("action=applied", result.stdout)

        lines = self.kubectl_lines()
        self.assertEqual(len(lines), 6, lines)
        self.assert_context_is_fixed_after_selection()
        self.assertIn("auth can-i patch deployment/guardian", lines[3])
        self.assertIn(
            f"--namespace {DEVNET_NAMESPACE} patch deployment guardian", lines[4]
        )
        self.assertNotIn("get deployment oracle", " ".join(lines))
        self.assertNotIn("patch deployment oracle", " ".join(lines))
        for resource in ("secret", "service", "ingress", "helm"):
            self.assertNotIn(f" {resource} ", f" {' '.join(lines)} ")

        patches = self.patches()
        self.assertEqual(len(patches), 1)
        self.assertIn(
            {"op": "test", "path": "/metadata/labels/app", "value": "guardian"},
            patches[0],
        )
        replacements = [operation for operation in patches[0] if operation["op"] == "replace"]
        self.assertEqual(
            replacements,
            [
                {
                    "op": "replace",
                    "path": "/spec/template/spec/containers/0/image",
                    "value": DESIRED_IMAGES["guardian"],
                }
            ],
        )
        replica_tests = [
            operation
            for operation in patches[0]
            if operation["op"] == "test" and operation["path"] == "/spec/replicas"
        ]
        self.assertEqual(replica_tests, [{"op": "test", "path": "/spec/replicas", "value": 0}])
        self.assertEqual(
            json.loads(self.state.read_text(encoding="utf-8"))["spec"]["replicas"], 0
        )

    def test_stale_forward_patch_does_not_undo_a_concurrent_desired_image(self) -> None:
        current = "docker.io/switchboardlabs/guardian:devnet"
        self.write_live_state(deployment("guardian", DEVNET_NAMESPACE, 0, current))
        result = self.run_script(
            "--network",
            "devnet",
            "--host-id",
            "stra01",
            "--expected-current-image",
            current,
            "--apply",
            extra_env={"KUBECTL_RACE_TO_DESIRED_BEFORE_FORWARD": "1"},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("forward image patch was not confirmed", result.stderr)
        self.assertIn("no automatic rollback was attempted", result.stderr)
        self.assertIn(f"operator recovery image is {current}", result.stderr)
        self.assertEqual(len(self.kubectl_lines()), 5)
        self.assertEqual(self.patches(), [])

        live = json.loads(self.state.read_text(encoding="utf-8"))
        self.assertEqual(
            live["spec"]["template"]["spec"]["containers"][0]["image"],
            DESIRED_IMAGES["guardian"],
        )
        self.assertEqual(live["metadata"]["resourceVersion"], "18")
        self.assertEqual(live["spec"]["replicas"], 0)

    def test_unconfirmed_forward_response_does_not_attempt_rollback(self) -> None:
        current = "docker.io/switchboardlabs/guardian:devnet"
        self.write_live_state(deployment("guardian", DEVNET_NAMESPACE, 0, current))
        result = self.run_script(
            "--network",
            "devnet",
            "--host-id",
            "stra01",
            "--expected-current-image",
            current,
            "--apply",
            extra_env={"KUBECTL_UNCONFIRMED_FORWARD_RESPONSE": "1"},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("forward image patch was not confirmed", result.stderr)
        self.assertIn("no automatic rollback was attempted", result.stderr)
        self.assertIn(f"operator recovery image is {current}", result.stderr)
        self.assertEqual(len(self.kubectl_lines()), 5)
        self.assertEqual(len(self.patches()), 1)

        live = json.loads(self.state.read_text(encoding="utf-8"))
        self.assertEqual(
            live["spec"]["template"]["spec"]["containers"][0]["image"],
            DESIRED_IMAGES["guardian"],
        )
        self.assertEqual(live["spec"]["replicas"], 0)

    def test_failed_post_check_restores_and_confirms_the_previous_image(self) -> None:
        current = "docker.io/switchboardlabs/guardian:devnet"
        self.write_live_state(deployment("guardian", DEVNET_NAMESPACE, 0, current))
        result = self.run_script(
            "--network",
            "devnet",
            "--host-id",
            "stra01",
            "--expected-current-image",
            current,
            "--apply",
            extra_env={"KUBECTL_FAIL_FIRST_POST_PATCH_GET": "1"},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("recovery=restored", result.stderr)
        self.assertIn(f"operator recovery image is {current}", result.stderr)
        self.assertEqual(len(self.kubectl_lines()), 9)

        patches = self.patches()
        self.assertEqual(len(patches), 2)
        self.assertEqual(
            [
                operation
                for operation in patches[1]
                if operation["op"] == "replace"
            ],
            [
                {
                    "op": "replace",
                    "path": "/spec/template/spec/containers/0/image",
                    "value": current,
                }
            ],
        )
        live = json.loads(self.state.read_text(encoding="utf-8"))
        self.assertEqual(live["spec"]["template"]["spec"]["containers"][0]["image"], current)
        self.assertEqual(live["spec"]["replicas"], 0)

    def test_unproven_recovery_reports_the_exact_operator_image(self) -> None:
        current = "docker.io/switchboardlabs/guardian:devnet"
        self.write_live_state(deployment("guardian", DEVNET_NAMESPACE, 0, current))
        result = self.run_script(
            "--network",
            "devnet",
            "--host-id",
            "stra01",
            "--expected-current-image",
            current,
            "--apply",
            extra_env={
                "KUBECTL_FAIL_FIRST_POST_PATCH_GET": "1",
                "KUBECTL_ROLLBACK_FAIL": "1",
            },
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("recovery could not be proven", result.stderr)
        self.assertIn(f"operator recovery image is {current}", result.stderr)
        self.assertEqual(len(self.kubectl_lines()), 8)
        self.assertEqual(len(self.patches()), 1)


if __name__ == "__main__":
    unittest.main()
