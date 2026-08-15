#!/usr/bin/env python3

import base64
import gzip
import importlib.util
from pathlib import Path
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "k8s-oracle-agent-policy.py"
SPEC = importlib.util.spec_from_file_location("oracle_agent_policy", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)

CURRENT = "docker.io/switchboardlabs/oracle@sha256:" + "a" * 64
DESIRED = "docker.io/switchboardlabs/oracle@sha256:" + "b" * 64
STALE = "docker.io/switchboardlabs/oracle@sha256:" + "c" * 64

POLICY = f'''package agent_policy

default AllowRequestsFailingPolicy := false
default SetPolicyRequest := false
default ExecProcessRequest := false
default CreateContainerRequest := false

allowed_images := [
        "{STALE}",
        "pause",
]

CreateContainerRequest {{
         every storage in input.storages {{
                 some allowed_image in allowed_images
                 storage.source == allowed_image
         }}
}}
'''


class OracleAgentPolicyTest(unittest.TestCase):
    def test_replaces_stale_allowlist_with_current_and_desired_images(self):
        updated = MODULE.update_policy(POLICY, CURRENT, DESIRED)

        self.assertIn(f'"{CURRENT}"', updated)
        self.assertIn(f'"{DESIRED}"', updated)
        self.assertIn('"pause"', updated)
        self.assertNotIn(STALE, updated)
        for required in MODULE.REQUIRED_POLICY_TEXT:
            self.assertEqual(updated.count(required), 1)

    def test_round_trip_encoding_is_value_preserving(self):
        encoded = MODULE.encode_policy(POLICY)
        self.assertEqual(MODULE.decode_policy(encoded), POLICY)
        self.assertNotIn("\n", encoded)

    def test_rejects_missing_fail_closed_clause(self):
        weakened = POLICY.replace("default ExecProcessRequest := false\n", "")
        with self.assertRaisesRegex(ValueError, "fail-closed policy clause"):
            MODULE.update_policy(weakened, CURRENT, DESIRED)

    def test_rejects_non_digest_image(self):
        with self.assertRaisesRegex(ValueError, "invalid immutable Oracle image"):
            MODULE.image_ref("docker.io/switchboardlabs/oracle:mainnet")

    def test_encoded_output_decodes_as_gzip(self):
        encoded = MODULE.encode_policy(POLICY)
        decoded = gzip.decompress(base64.b64decode(encoded)).decode("utf-8")
        self.assertEqual(decoded, POLICY)


if __name__ == "__main__":
    unittest.main()
