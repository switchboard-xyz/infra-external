#!/usr/bin/env python3
"""Update an existing confidential-container policy for an Oracle rollout."""

import argparse
import base64
import gzip
import re
import sys


ORACLE_IMAGE_RE = re.compile(
    r"^docker\.io/switchboardlabs/oracle@sha256:[0-9a-f]{64}$"
)
ALLOWED_IMAGES_RE = re.compile(
    r"(?ms)^allowed_images\s*:=\s*\[.*?^\]"
)
REQUIRED_POLICY_TEXT = (
    "package agent_policy",
    "default AllowRequestsFailingPolicy := false",
    "default SetPolicyRequest := false",
    "default ExecProcessRequest := false",
    "default CreateContainerRequest := false",
    "every storage in input.storages",
    "storage.source == allowed_image",
)


def image_ref(value: str) -> str:
    if not ORACLE_IMAGE_RE.fullmatch(value):
        raise ValueError(f"invalid immutable Oracle image reference: {value!r}")
    return value


def decode_policy(encoded: str) -> str:
    try:
        compressed = base64.b64decode(encoded, validate=True)
        return gzip.decompress(compressed).decode("utf-8")
    except (ValueError, OSError, UnicodeDecodeError) as err:
        raise ValueError("existing confidential-container policy is invalid") from err


def encode_policy(policy: str) -> str:
    return base64.b64encode(gzip.compress(policy.encode("utf-8"), mtime=0)).decode(
        "ascii"
    )


def update_policy(policy: str, current_image: str, desired_image: str) -> str:
    for required in REQUIRED_POLICY_TEXT:
        if policy.count(required) != 1:
            raise ValueError(f"required fail-closed policy clause is missing or ambiguous: {required}")

    matches = list(ALLOWED_IMAGES_RE.finditer(policy))
    if len(matches) != 1:
        raise ValueError("allowed_images policy block is missing or ambiguous")

    allowed_images = list(dict.fromkeys((current_image, desired_image)))
    rendered = "allowed_images := [\n"
    rendered += "".join(f'        "{image}",\n' for image in allowed_images)
    rendered += '        "pause",\n]'

    updated = ALLOWED_IMAGES_RE.sub(rendered, policy, count=1)
    if "{{IMAGE_" in updated:
        raise ValueError("unresolved image placeholder remains in policy")
    return updated


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--current-image", required=True, type=image_ref)
    parser.add_argument("--desired-image", required=True, type=image_ref)
    args = parser.parse_args()

    encoded = sys.stdin.read().strip()
    if not encoded:
        raise ValueError("existing confidential-container policy is absent")

    policy = decode_policy(encoded)
    updated = update_policy(policy, args.current_image, args.desired_image)
    sys.stdout.write(encode_policy(updated))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as err:
        print(str(err), file=sys.stderr)
        raise SystemExit(1) from err
