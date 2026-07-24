#!/usr/bin/env bash
set -Eeuo pipefail

target_host="${1:-}"
cluster="${2:-}"
image_digest="${GUARDIAN_IMAGE_DIGEST:-}"
remediator_enabled="${GUARDIAN_REMEDIATOR_ENABLED:-false}"
ephemeral_storage_enabled="${GUARDIAN_EPHEMERAL_STORAGE_ENABLED:-false}"
fallback_enabled="${GUARDIAN_PUBLIC_RPC_FALLBACK_ENABLED:-true}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
health_script="${script_dir}/guardian-fleet-health.sh"
ssh_key="${SWITCHBOARD_INFRA_SSH_KEY:-}"
known_hosts="${SWITCHBOARD_INFRA_KNOWN_HOSTS:-}"

fail() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

[[ "${target_host}" =~ ^[a-zA-Z0-9.-]+$ ]] ||
  fail "target host must be an explicit hostname or IPv4 address"
[[ "${cluster}" == "devnet" || "${cluster}" == "mainnet" ]] ||
  fail "cluster must be devnet or mainnet"
[[ "${image_digest}" =~ ^sha256:[a-f0-9]{64}$ ]] ||
  fail "GUARDIAN_IMAGE_DIGEST must be an immutable sha256 digest"
[[ "${remediator_enabled}" == "true" || "${remediator_enabled}" == "false" ]] ||
  fail "GUARDIAN_REMEDIATOR_ENABLED must be true or false"
[[ "${ephemeral_storage_enabled}" == "true" || "${ephemeral_storage_enabled}" == "false" ]] ||
  fail "GUARDIAN_EPHEMERAL_STORAGE_ENABLED must be true or false"
[[ "${fallback_enabled}" == "true" || "${fallback_enabled}" == "false" ]] ||
  fail "GUARDIAN_PUBLIC_RPC_FALLBACK_ENABLED must be true or false"
[[ -n "${ssh_key}" && -r "${ssh_key}" ]] ||
  fail "SWITCHBOARD_INFRA_SSH_KEY must name a readable SSH private key"
[[ -n "${known_hosts}" && -r "${known_hosts}" ]] ||
  fail "SWITCHBOARD_INFRA_KNOWN_HOSTS must name a readable known-hosts file"
[[ -x "${health_script}" ]] || fail "guardian fleet health checker is not executable"
[[ -n "${GUARDIAN_FLEET_INVENTORY:-}" && -r "${GUARDIAN_FLEET_INVENTORY}" ]] ||
  fail "GUARDIAN_FLEET_INVENTORY must name a readable inventory file"
awk -F '|' -v target="${target_host}" -v expected_cluster="${cluster}" \
  '$1 == target && $2 == expected_cluster { found = 1 } END { exit !found }' \
  "${GUARDIAN_FLEET_INVENTORY}" ||
  fail "target host is not assigned to ${cluster} in GUARDIAN_FLEET_INVENTORY"

check_fleet() {
  local healthy
  healthy="$(GUARDIAN_FLEET_CLUSTER="${cluster}" "${health_script}")"
  [[ "${healthy}" =~ ^[0-9]+$ ]] || fail "fleet health checker did not return an integer"
  ((healthy >= 5)) || fail "only ${healthy} fleet-healthy guardians; at least 5 are required"
  printf "%s\n" "${healthy}"
}

healthy_before="$(check_fleet)"
attested_at="$(date +%s)"

ssh -n -T \
  -i "${ssh_key}" \
  -o IdentityAgent=none \
  -o IdentitiesOnly=yes \
  -o BatchMode=yes \
  -o StrictHostKeyChecking=yes \
  -o "UserKnownHostsFile=${known_hosts}" \
  -o ConnectTimeout=6 \
  -o LogLevel=ERROR \
  "root@${target_host}" /bin/bash -s -- \
  "${cluster}" \
  "${image_digest}" \
  "${remediator_enabled}" \
  "${ephemeral_storage_enabled}" \
  "${fallback_enabled}" \
  "${healthy_before}" \
  "${attested_at}" <<'REMOTE'
set -Eeuo pipefail

cluster="$1"
image_digest="$2"
remediator_enabled="$3"
ephemeral_storage_enabled="$4"
fallback_enabled="$5"
healthy_before="$6"
attested_at="$7"
repo_dir="/root/infra-external"

[[ -d "${repo_dir}/.git" ]]
[[ -z "$(git -C "${repo_dir}" status --porcelain --untracked-files=all)" ]]
upstream="$(git -C "${repo_dir}" rev-parse --abbrev-ref '@{upstream}')"
git -C "${repo_dir}" fetch
local_head="$(git -C "${repo_dir}" rev-parse HEAD)"
upstream_head="$(git -C "${repo_dir}" rev-parse "${upstream}")"
git -C "${repo_dir}" merge-base --is-ancestor "${local_head}" "${upstream_head}"
git -C "${repo_dir}" merge --ff-only "${upstream}"

export GUARDIAN_IMAGE_DIGEST="${image_digest}"
export GUARDIAN_REMEDIATOR_ENABLED="${remediator_enabled}"
export GUARDIAN_EPHEMERAL_STORAGE_ENABLED="${ephemeral_storage_enabled}"
export GUARDIAN_PUBLIC_RPC_FALLBACK_ENABLED="${fallback_enabled}"
export GUARDIAN_FLEET_HEALTH_COUNT="${healthy_before}"
export GUARDIAN_FLEET_HEALTH_ATTESTED_AT="${attested_at}"
exec "${repo_dir}/.scripts/kubernetes/k8s-oracle-install.sh" "${cluster}"
REMOTE

healthy_after="$(check_fleet)"
printf "guardian rollout completed on %s; fleet healthy before=%s after=%s\n" \
  "${target_host}" "${healthy_before}" "${healthy_after}"
