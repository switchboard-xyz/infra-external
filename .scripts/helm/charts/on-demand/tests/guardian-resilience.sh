#!/usr/bin/env bash
set -Eeuo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -f "${tmp_dir}"/*.yaml; rmdir "${tmp_dir}"' EXIT

digest="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
guardian_render="${tmp_dir}/guardian.yaml"
remediator_render="${tmp_dir}/remediator.yaml"
tag_render="${tmp_dir}/guardian-tag.yaml"
storage_render="${tmp_dir}/guardian-storage.yaml"
all_render="${tmp_dir}/all.yaml"

helm lint "${chart_dir}" \
  --set-string "components.guardian.imageDigest=${digest}" \
  --set "components.guardian.remediator.enabled=true"

helm template guardian-test "${chart_dir}" \
  --show-only templates/guardian.yaml \
  --set-string "components.guardian.imageDigest=${digest}" \
  --set "components.guardian.remediator.enabled=true" \
  --set-string "pagerDutySecret.name=guardian-pagerduty" \
  >"${guardian_render}"
helm template guardian-test "${chart_dir}" \
  --show-only templates/guardian-remediator.yaml \
  --set-string "components.guardian.imageDigest=${digest}" \
  --set "components.guardian.remediator.enabled=true" \
  >"${remediator_render}"
helm template guardian-test "${chart_dir}" \
  --show-only templates/guardian.yaml \
  --set "components.guardian.remediator.enabled=false" \
  >"${tag_render}"
helm template guardian-test "${chart_dir}" \
  --show-only templates/guardian.yaml \
  --set-string "components.guardian.imageDigest=${digest}" \
  --set "components.guardian.ephemeralStorage.enabled=true" \
  >"${storage_render}"
helm template guardian-test "${chart_dir}" \
  --set-string "components.guardian.imageDigest=${digest}" \
  --set "components.guardian.remediator.enabled=true" \
  >"${all_render}"

rg -q 'type: Recreate' "${guardian_render}"
rg -q "image: \"docker.io/switchboardlabs/guardian@${digest}\"" "${guardian_render}"
rg -q 'path: /ready' "${guardian_render}"
rg -q 'name: HEARTBEAT_RPC_FALLBACK_URLS' "${guardian_render}"
rg -q 'name: "jupiter-swap-api"' "${guardian_render}"
rg -q 'name: payer-secret' "${guardian_render}"
rg -q 'name: PAGERDUTY_API_KEY' "${guardian_render}"
rg -q 'name: "guardian-pagerduty"' "${guardian_render}"
if rg -q 'keel\.sh/' "${guardian_render}"; then
  printf "digest-pinned guardian unexpectedly contains Keel annotations\n" >&2
  exit 1
fi

rg -q 'resourceNames: \["guardian"\]' "${remediator_render}"
rg -q 'verbs: \["get", "patch"\]' "${remediator_render}"
rg -q 'concurrencyPolicy: Forbid' "${remediator_render}"
rg -q 'readOnlyRootFilesystem: true' "${remediator_render}"
rg -q 'runAsNonRoot: true' "${remediator_render}"
if rg -q 'verbs:.*delete|PAYER_SECRET|RPC_URL|runtimeClassName' "${remediator_render}"; then
  printf "remediator manifest contains forbidden authority or guardian configuration\n" >&2
  exit 1
fi

install_script="$(dirname "${chart_dir}")/../../kubernetes/k8s-oracle-install.sh"
fleet_script="$(dirname "${chart_dir}")/../../kubernetes/guardian-fleet-health.sh"
rollout_script="$(dirname "${chart_dir}")/../../kubernetes/guardian-rollout-one.sh"
rg -q 'verify_fleet_health_attestation' "${install_script}"
rg -q 'validate_secret_inputs' "${install_script}"
rg -q 'StrictHostKeyChecking=yes' "${fleet_script}" "${rollout_script}"
rg -q 'k3s kubectl' "${fleet_script}"
rg -F -q "go-template='{{len .items}}'" "${fleet_script}"
rg -q 'GUARDIAN_FLEET_CLUSTER=.*cluster' "${rollout_script}"
rg -q 'deployed_cluster.*expected_cluster' "${fleet_script}"
rg -q 'heartbeat_interval.*expected_heartbeat_interval' "${fleet_script}"
rg -q '\$1 == target && \$2 == expected_cluster' "${rollout_script}"
if rg -q 'kubectl --context' "${fleet_script}"; then
  printf "fleet health checker must use the bare-metal SSH/k3s access path\n" >&2
  exit 1
fi
preflight_line="$(rg -n '^validate_secret_inputs$' "${install_script}" | cut -d: -f1)"
lint_line="$(rg -n '^helm lint ' "${install_script}" | cut -d: -f1)"
mutation_line="$(rg -n '^ensure_namespace$' "${install_script}" | cut -d: -f1)"
if ((preflight_line >= mutation_line || lint_line >= mutation_line)); then
  printf "installer mutates Kubernetes before completing read-only preflights\n" >&2
  exit 1
fi

rg -q 'keel\.sh/trigger: "poll"' "${tag_render}"
rg -q 'image: "docker.io/switchboardlabs/guardian:devnet"' "${tag_render}"
if rg -q 'ephemeral-storage:' "${guardian_render}"; then
  printf "ephemeral-storage rendered before Kata accounting was explicitly enabled\n" >&2
  exit 1
fi
rg -q 'ephemeral-storage: 8Gi' "${storage_render}"
rg -q 'ephemeral-storage: 1Gi' "${storage_render}"

if helm template guardian-test "${chart_dir}" \
  --set "components.guardian.remediator.enabled=true" >/dev/null 2>&1; then
  printf "remediator rendered without an immutable image digest\n" >&2
  exit 1
fi

if rg -n '^jupiterSwapApiKey:' "${chart_dir}" "$(dirname "${chart_dir}")/../cfg"; then
  printf "plaintext Jupiter API key value remains in Helm source\n" >&2
  exit 1
fi
if rg -U -q 'name: (JUPITER_SWAP_API_KEY|PAYER_SECRET)\n[[:space:]]+value:' "${all_render}"; then
  printf "a credential environment variable rendered as plaintext\n" >&2
  exit 1
fi

printf "guardian Helm resilience assertions passed\n"
