#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp_dir="$(mktemp -d "${script_dir}/.guardian-fleet-test.XXXXXX")"
trap 'rm -f "${tmp_dir}/inventory" "${tmp_dir}/key" "${tmp_dir}/known_hosts" "${tmp_dir}/ssh" "${tmp_dir}/ssh.log" "${tmp_dir}/rollout.log"; rmdir "${tmp_dir}"' EXIT

touch "${tmp_dir}/key" "${tmp_dir}/known_hosts" "${tmp_dir}/ssh.log"
cat >"${tmp_dir}/inventory" <<'INVENTORY'
healthy-1|devnet|switchboard-oracle-devnet|30
healthy-2|devnet|switchboard-oracle-devnet|30
healthy-3|devnet|switchboard-oracle-devnet|30
healthy-4|devnet|switchboard-oracle-devnet|30
healthy-5|devnet|switchboard-oracle-devnet|30
unhealthy-1|devnet|switchboard-oracle-devnet|30
healthy-mainnet-1|mainnet|switchboard-oracle-mainnet|30
INVENTORY
cat >"${tmp_dir}/ssh" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
printf "%s\n" "$*" >>"${MOCK_SSH_LOG}"
for argument in "$@"; do
  if [[ "${argument}" == "root@unhealthy-1" ]]; then
    exit 1
  fi
done
printf "1\n"
MOCK
chmod 0755 "${tmp_dir}/ssh"

healthy="$(
  PATH="${tmp_dir}:${PATH}" \
    MOCK_SSH_LOG="${tmp_dir}/ssh.log" \
    GUARDIAN_FLEET_INVENTORY="${tmp_dir}/inventory" \
    GUARDIAN_FLEET_CLUSTER=devnet \
    SWITCHBOARD_INFRA_SSH_KEY="${tmp_dir}/key" \
    SWITCHBOARD_INFRA_KNOWN_HOSTS="${tmp_dir}/known_hosts" \
    "${script_dir}/guardian-fleet-health.sh"
)"
[[ "${healthy}" == "5" ]]
grep -q -- '-o IdentityAgent=none' "${tmp_dir}/ssh.log"
grep -q -- '-o IdentitiesOnly=yes' "${tmp_dir}/ssh.log"
grep -q -- '-o BatchMode=yes' "${tmp_dir}/ssh.log"
grep -q -- '-o StrictHostKeyChecking=yes' "${tmp_dir}/ssh.log"
grep -q -- 'k3s' "${script_dir}/guardian-fleet-health.sh"
grep -q -- 'GUARDIAN_FLEET_CLUSTER="${cluster}"' "${script_dir}/guardian-rollout-one.sh"

if GUARDIAN_FLEET_INVENTORY="${tmp_dir}/inventory" \
  SWITCHBOARD_INFRA_SSH_KEY="${tmp_dir}/key" \
  SWITCHBOARD_INFRA_KNOWN_HOSTS="${tmp_dir}/known_hosts" \
  GUARDIAN_IMAGE_DIGEST="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" \
  "${script_dir}/guardian-rollout-one.sh" healthy-1 mainnet \
  >"${tmp_dir}/rollout.log" 2>&1; then
  printf "rollout accepted a host assigned to a different cluster\n" >&2
  exit 1
fi
grep -q -- 'not assigned to mainnet' "${tmp_dir}/rollout.log"

printf "guardian fleet health assertions passed\n"
