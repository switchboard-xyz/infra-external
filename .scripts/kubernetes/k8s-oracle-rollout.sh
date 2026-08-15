#!/usr/bin/env bash
set -euo pipefail

network="${1:-}"
if [[ "${network}" != "devnet" && "${network}" != "mainnet" ]]; then
  printf 'usage: %s devnet|mainnet\n' "$0" >&2
  exit 2
fi

for command_name in helm kubectl python3; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    printf 'required command is unavailable: %s\n' "${command_name}" >&2
    exit 1
  fi
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(readlink -f "${script_dir}/../..")"
chart_dir="${repo_dir}/.scripts/helm/charts/on-demand"
policy_tool="${script_dir}/k8s-oracle-agent-policy.py"
values_file="${repo_dir}/.scripts/helm/cfg/${network}-solana-values.yaml"
common_cfg="${repo_dir}/cfg/00-common-vars.cfg"
network_cfg="${repo_dir}/cfg/00-${network}-vars.cfg"

for required_file in "${values_file}" "${common_cfg}" "${network_cfg}" "${policy_tool}"; do
  if [[ ! -f "${required_file}" ]]; then
    printf 'required rollout input is unavailable: %s\n' "${required_file}" >&2
    exit 1
  fi
done

# The existing host configuration is the authority for namespace and release
# identity. This entrypoint intentionally does not load, print, or recreate any
# payer material.
source "${common_cfg}"
source "${network_cfg}"
: "${NAMESPACE:?NAMESPACE is required}"
: "${NETWORK:?NETWORK is required}"

if [[ "${NETWORK}" != "${network}" ]]; then
  printf 'configured network %s does not match requested network %s\n' \
    "${NETWORK}" "${network}" >&2
  exit 1
fi

desired_digest="$({
  awk '
    /^components:/ { in_components = 1; next }
    in_components && /^    oracle:/ { in_oracle = 1; next }
    in_oracle && /^      imageDigest:/ {
      value = $0
      sub(/^[^:]+:[[:space:]]*/, "", value)
      gsub(/"/, "", value)
      print value
      exit
    }
    in_oracle && /^    [[:alnum:]_-]+:/ { exit }
  ' "${values_file}"
})"

if [[ ! "${desired_digest}" =~ ^sha256:[a-f0-9]{64}$ ]]; then
  printf 'invalid or missing Oracle image digest in %s\n' "${values_file}" >&2
  exit 1
fi

release="sb-oracle-${NETWORK}"
oracle_image="docker.io/switchboardlabs/oracle"

helm status "${release}" -n "${NAMESPACE}" >/dev/null

read_deployment_field() {
  local deployment="$1"
  local jsonpath="$2"
  if ! kubectl -n "${NAMESPACE}" get deployment "${deployment}" >/dev/null 2>&1; then
    printf '__absent__'
    return
  fi
  kubectl -n "${NAMESPACE}" get deployment "${deployment}" -o "jsonpath=${jsonpath}"
}

oracle_replicas_before="$(read_deployment_field oracle '{.spec.replicas}')"
oracle_image_before="$(read_deployment_field oracle '{.spec.template.spec.containers[0].image}')"
guardian_image_before="$(read_deployment_field guardian '{.spec.template.spec.containers[0].image}')"
guardian_replicas_before="$(read_deployment_field guardian '{.spec.replicas}')"
gateway_image_before="$(read_deployment_field gateway '{.spec.template.spec.containers[0].image}')"
gateway_replicas_before="$(read_deployment_field gateway '{.spec.replicas}')"
payer_ref_before="$(read_deployment_field oracle '{range .spec.template.spec.containers[0].env[?(@.name=="PAYER_SECRET")]}{.valueFrom.secretKeyRef.name}/{.valueFrom.secretKeyRef.key}{end}')"
sui_ref_before="$(read_deployment_field oracle '{range .spec.template.spec.containers[0].env[?(@.name=="SUI_MAINNET_RPC")]}{.valueFrom.secretKeyRef.name}/{.valueFrom.secretKeyRef.key}{end}')"
policy_before="$(read_deployment_field oracle '{.spec.template.metadata.annotations.io\.katacontainers\.config\.runtime\.cc_init_data}')"

# --reuse-values does not merge newly added chart defaults into an older Helm
# release. Pass the existing Sui Secret reference explicitly so the
# taskRunnerRpc object is present without reading or changing the Secret value.
sui_secret_name=""
sui_secret_key="SUI_MAINNET_RPC"
if [[ -n "${sui_ref_before}" ]]; then
  sui_secret_name="${sui_ref_before%%/*}"
  sui_secret_key="${sui_ref_before#*/}"
  if [[ -z "${sui_secret_name}" || -z "${sui_secret_key}" || "${sui_secret_key}" == "${sui_ref_before}" || "${sui_secret_key}" == */* ]]; then
    printf 'Oracle Sui RPC Secret reference is invalid before rollout\n' >&2
    exit 1
  fi
fi

if [[ "${oracle_replicas_before}" == "__absent__" ]]; then
  printf 'Oracle Deployment is absent in namespace %s\n' "${NAMESPACE}" >&2
  exit 1
fi
if [[ ! "${oracle_replicas_before}" =~ ^[0-9]+$ ]]; then
  printf 'Oracle replica count is invalid before rollout\n' >&2
  exit 1
fi

expected_image="${oracle_image}@${desired_digest}"
policy_after="$(printf '%s' "${policy_before}" | python3 "${policy_tool}" \
  --current-image "${oracle_image_before}" \
  --desired-image "${expected_image}")"

helm upgrade "${release}" "${chart_dir}" \
  -n "${NAMESPACE}" \
  --reuse-values \
  --set-string components.oracle.image="${oracle_image}" \
  --set-string components.oracle.imageDigest="${desired_digest}" \
  --set-string components.oracle.ccInitData="${policy_after}" \
  --set-string taskRunnerRpc.secretName="${sui_secret_name}" \
  --set-string taskRunnerRpc.suiMainnetRpcKey="${sui_secret_key}" \
  --set components.oracle.replicas="${oracle_replicas_before}" \
  --wait >/dev/null

oracle_image_after="$(read_deployment_field oracle '{.spec.template.spec.containers[0].image}')"
oracle_replicas_after="$(read_deployment_field oracle '{.spec.replicas}')"
guardian_image_after="$(read_deployment_field guardian '{.spec.template.spec.containers[0].image}')"
guardian_replicas_after="$(read_deployment_field guardian '{.spec.replicas}')"
gateway_image_after="$(read_deployment_field gateway '{.spec.template.spec.containers[0].image}')"
gateway_replicas_after="$(read_deployment_field gateway '{.spec.replicas}')"
payer_ref_after="$(read_deployment_field oracle '{range .spec.template.spec.containers[0].env[?(@.name=="PAYER_SECRET")]}{.valueFrom.secretKeyRef.name}/{.valueFrom.secretKeyRef.key}{end}')"
sui_ref_after="$(read_deployment_field oracle '{range .spec.template.spec.containers[0].env[?(@.name=="SUI_MAINNET_RPC")]}{.valueFrom.secretKeyRef.name}/{.valueFrom.secretKeyRef.key}{end}')"
policy_deployed="$(read_deployment_field oracle '{.spec.template.metadata.annotations.io\.katacontainers\.config\.runtime\.cc_init_data}')"

[[ "${oracle_image_after}" == "${expected_image}" ]] || {
  printf 'Oracle image mismatch after rollout\n' >&2
  exit 1
}
[[ "${oracle_replicas_after}" == "${oracle_replicas_before}" ]] || {
  printf 'Oracle replica count changed during rollout\n' >&2
  exit 1
}
[[ "${guardian_image_after}" == "${guardian_image_before}" ]] || {
  printf 'Guardian image changed during Oracle rollout\n' >&2
  exit 1
}
[[ "${guardian_replicas_after}" == "${guardian_replicas_before}" ]] || {
  printf 'Guardian replica count changed during Oracle rollout\n' >&2
  exit 1
}
[[ "${gateway_image_after}" == "${gateway_image_before}" ]] || {
  printf 'Gateway image changed during Oracle rollout\n' >&2
  exit 1
}
[[ "${gateway_replicas_after}" == "${gateway_replicas_before}" ]] || {
  printf 'Gateway replica count changed during Oracle rollout\n' >&2
  exit 1
}
[[ "${payer_ref_after}" == "${payer_ref_before}" ]] || {
  printf 'Oracle payer Secret reference changed during rollout\n' >&2
  exit 1
}
[[ "${sui_ref_after}" == "${sui_ref_before}" ]] || {
  printf 'Oracle Sui RPC Secret reference changed during rollout\n' >&2
  exit 1
}
[[ "${policy_deployed}" == "${policy_after}" ]] || {
  printf 'Oracle confidential-container policy changed during rollout\n' >&2
  exit 1
}

printf 'Oracle rollout completed for %s at %s\n' "${network}" "${desired_digest}"
