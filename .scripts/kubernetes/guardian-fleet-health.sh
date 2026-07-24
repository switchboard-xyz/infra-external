#!/usr/bin/env bash
set -Eeuo pipefail

inventory="${GUARDIAN_FLEET_INVENTORY:-}"
ssh_key="${SWITCHBOARD_INFRA_SSH_KEY:-}"
known_hosts="${SWITCHBOARD_INFRA_KNOWN_HOSTS:-}"
required_cluster="${GUARDIAN_FLEET_CLUSTER:-}"

# One pipe-delimited row per bare-metal host:
# ssh-host|cluster|namespace|heartbeat-interval-seconds
[[ -n "${inventory}" && -r "${inventory}" ]] || {
  printf "GUARDIAN_FLEET_INVENTORY must name a readable inventory file\n" >&2
  exit 1
}
[[ -n "${ssh_key}" && -r "${ssh_key}" ]] || {
  printf "SWITCHBOARD_INFRA_SSH_KEY must name a readable SSH private key\n" >&2
  exit 1
}
[[ -n "${known_hosts}" && -r "${known_hosts}" ]] || {
  printf "SWITCHBOARD_INFRA_KNOWN_HOSTS must name a readable known-hosts file\n" >&2
  exit 1
}
[[ -z "${required_cluster}" || "${required_cluster}" =~ ^(devnet|mainnet)$ ]] || {
  printf "GUARDIAN_FLEET_CLUSTER must be devnet or mainnet when set\n" >&2
  exit 1
}

healthy=0
while IFS='|' read -r host cluster namespace heartbeat_interval extra; do
  [[ -n "${host}" ]] || continue
  [[ "${host}" == \#* ]] && continue
  if [[ -n "${extra}" ||
    ! "${host}" =~ ^[a-zA-Z0-9.-]+$ ||
    ! "${cluster}" =~ ^(devnet|mainnet)$ ||
    ! "${namespace}" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ||
    ! "${heartbeat_interval}" =~ ^[1-9][0-9]*$ ]]; then
    printf "invalid guardian fleet inventory row\n" >&2
    exit 1
  fi
  [[ -z "${required_cluster}" || "${cluster}" == "${required_cluster}" ]] || continue

  if result="$(
    ssh -n -T \
      -i "${ssh_key}" \
      -o IdentityAgent=none \
      -o IdentitiesOnly=yes \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=yes \
      -o "UserKnownHostsFile=${known_hosts}" \
      -o ConnectTimeout=6 \
      -o LogLevel=ERROR \
      "root@${host}" /bin/bash -s -- \
      "${namespace}" "${heartbeat_interval}" "${cluster}" <<'REMOTE'
set -Eeuo pipefail

namespace="$1"
expected_heartbeat_interval="$2"
expected_cluster="$3"

deployment="$(
  k3s kubectl -n "${namespace}" get deployment guardian \
    -o jsonpath='{.spec.replicas}|{.status.readyReplicas}|{.status.availableReplicas}|{.status.unavailableReplicas}'
)"
IFS='|' read -r desired ready available unavailable <<<"${deployment}"
[[ "${desired}" == "1" && "${ready}" == "1" && "${available}" == "1" ]]
[[ -z "${unavailable}" || "${unavailable}" == "0" ]]

deployed_cluster="$(
  k3s kubectl -n "${namespace}" get deployment guardian \
    -o jsonpath='{.metadata.labels.cluster}'
)"
[[ "${deployed_cluster}" == "${expected_cluster}" ]]

pod_count="$(
  k3s kubectl -n "${namespace}" get pods -l app=guardian \
    -o go-template='{{len .items}}'
)"
[[ "${pod_count}" == "1" ]]

pod="$(
  k3s kubectl -n "${namespace}" get pods -l app=guardian \
    -o jsonpath='{.items[0].status.podIP}|{.items[0].status.conditions[?(@.type=="Ready")].status}|{.items[0].status.containerStatuses[0].restartCount}'
)"
IFS='|' read -r pod_ip pod_ready restart_count <<<"${pod}"
[[ -n "${pod_ip}" && "${pod_ready}" == "True" && "${restart_count}" =~ ^[0-9]+$ ]]

guardian_port="$(
  k3s kubectl -n "${namespace}" get deployment guardian \
    -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="GUARDIAN_PORT")].value}'
)"
[[ "${guardian_port}" =~ ^[1-9][0-9]*$ ]]
heartbeat_interval="$(
  k3s kubectl -n "${namespace}" get deployment guardian \
    -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="HEARTBEAT_INTERVAL")].value}'
)"
[[ "${heartbeat_interval}" =~ ^[1-9][0-9]*$ ]]
[[ "${heartbeat_interval}" == "${expected_heartbeat_interval}" ]]

curl -fsS --max-time 5 \
  -H 'content-type: application/json' \
  --data '{"api_version":"1"}' \
  "http://${pod_ip}:${guardian_port}/guardian/api/v1/test" >/dev/null

onchain_age="$(
  curl -fsS --max-time 5 "http://${pod_ip}:9090/metrics" |
    awk '/switchboard_on_demand_heartbeat_onchain_age_gauge/ && /role="guardian"/ { print $NF; exit }'
)"
[[ "${onchain_age}" =~ ^[0-9]+([.][0-9]+)?$ ]]
maximum_age=$((2 * heartbeat_interval + 60))
awk -v age="${onchain_age}" -v maximum="${maximum_age}" \
  'BEGIN { exit !(age <= maximum) }'

printf "1\n"
REMOTE
  )" && [[ "${result}" == "1" ]]; then
    healthy=$((healthy + 1))
  else
    printf "guardian host %s is not fleet-healthy\n" "${host}" >&2
  fi
done <"${inventory}"

printf "%s\n" "${healthy}"
