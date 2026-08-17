#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chart_dir="$(readlink -f "${script_dir}/..")"
cfg_dir="$(readlink -f "${chart_dir}/../../cfg")"

render_component() {
  local component="$1"
  shift
  helm template gateway-readiness "${chart_dir}" \
    --show-only "templates/${component}.yaml" \
    "$@"
}

render_component_hash() {
  local component="$1"
  shift
  helm template gateway-default "${chart_dir}" \
    --show-only "templates/${component}.yaml" \
    "$@" |
    sha256sum |
    awk '{ print $1 }'
}

gateway_default_hash="c58f0509140ba830fb4ec39e461f84197318353c326aaa7c0864a3c46ebcb476"
mainnet_default_hash="94fe0830efe0c96cc768c96e03fb94a19020b6bd8107c841f7b8b4a5a3547584"
oracle_default_hash="00f6a207575fd62f5fbd928c5c3666449a84e549159617b367a3599f4607ae8a"
guardian_default_hash="f555dd99131820be7432284645812c4a490c3ac816826c08a4c71a734f8f624f"

[[ "$(render_component_hash gateway)" == "${gateway_default_hash}" ]]
[[ "$(render_component_hash oracle)" == "${oracle_default_hash}" ]]
[[ "$(render_component_hash guardian)" == "${guardian_default_hash}" ]]
[[ "$(
  render_component_hash oracle \
    --set components.gateway.readinessProbe.enabled=true
)" == "${oracle_default_hash}" ]]
[[ "$(
  render_component_hash guardian \
    --set components.gateway.readinessProbe.enabled=true
)" == "${guardian_default_hash}" ]]
[[ "$(
  helm template gateway-mainnet "${chart_dir}" \
    -f "${cfg_dir}/mainnet-solana-values.yaml" |
    sha256sum |
    awk '{ print $1 }'
)" == "${mainnet_default_hash}" ]]

gateway_default_render="$(render_component gateway)"
! grep -q '^        readinessProbe:$' <<<"${gateway_default_render}"

gateway_opt_in_render="$(
  render_component gateway \
    --set components.gateway.readinessProbe.enabled=true \
    --set-string components.gateway.metrics.path=/authoritative-gateway-metrics \
    --set components.gateway.metrics.port=9191
)"
readiness_through_sibling="$(
  awk '
    /^        readinessProbe:$/ { capture = 1 }
    capture && NF { print }
    capture && /^        resources:$/ { exit }
  ' <<<"${gateway_opt_in_render}"
)"
expected_readiness_through_sibling='        readinessProbe:
          httpGet:
            path: /authoritative-gateway-metrics
            port: 9191
        resources:'
[[ "${readiness_through_sibling}" == "${expected_readiness_through_sibling}" ]]

printf 'Gateway readiness Helm render checks passed\n'
