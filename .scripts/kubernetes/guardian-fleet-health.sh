#!/usr/bin/env bash
set -Eeuo pipefail

inventory="${GUARDIAN_FLEET_INVENTORY:-}"
# One pipe-delimited row per host:
# kube-context|namespace|guardian-ping-url|metrics-url|heartbeat-interval-seconds
[[ -n "${inventory}" && -r "${inventory}" ]] || {
  printf "GUARDIAN_FLEET_INVENTORY must name a readable inventory file\n" >&2
  exit 1
}

healthy=0
while IFS='|' read -r context namespace ping_url metrics_url heartbeat_interval; do
  [[ -n "${context}" ]] || continue
  [[ "${context}" == \#* ]] && continue
  if [[ -z "${namespace}" || -z "${ping_url}" || -z "${metrics_url}" ||
    ! "${heartbeat_interval}" =~ ^[0-9]+$ ]]; then
    printf "invalid guardian fleet inventory row\n" >&2
    exit 1
  fi

  available="$(kubectl --context "${context}" -n "${namespace}" get deployment guardian \
    -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)"
  [[ "${available}" == "1" ]] || continue

  curl -fsS --max-time 5 \
    -H 'content-type: application/json' \
    --data '{"api_version":"1"}' \
    "${ping_url}" >/dev/null || continue

  onchain_age="$(
    curl -fsS --max-time 5 "${metrics_url}" |
      awk '/switchboard_on_demand_heartbeat_onchain_age_gauge/ && /role="guardian"/ { print $NF; exit }'
  )" || true
  [[ "${onchain_age}" =~ ^[0-9]+([.][0-9]+)?$ ]] || continue
  maximum_age=$((2 * heartbeat_interval + 60))
  awk -v age="${onchain_age}" -v maximum="${maximum_age}" \
    'BEGIN { exit !(age <= maximum) }' || continue

  healthy=$((healthy + 1))
done <"${inventory}"

printf "%s\n" "${healthy}"
