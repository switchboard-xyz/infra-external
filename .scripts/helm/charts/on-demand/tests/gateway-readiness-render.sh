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

gateway_default_hash="09a4499a0cbe0cd863f2631bcec1fb96101a397f6e68566e12b757b364575862"
mainnet_default_hash="2d0cace98f173d46f6848cfa5026b549aef14aeea353028454904f317f9ef8ef"
oracle_default_hash="90c7210703cab5c261b71231dc6b2d50877f7ca395c39ccab25d4a238b997cfa"
guardian_default_hash="38a0df206e18ddbdea8cb4ec867967d7a2f3004506b3cbccd0559ecfdb9a1f6f"

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

# An older Helm release reused with the new chart has no readinessProbe parent
# object. A null override exercises the same nil lookup without merging in the
# new chart default.
gateway_missing_readiness_render="$(
  render_component gateway \
    --set-json components.gateway.readinessProbe=null
)"
! grep -q '^        readinessProbe:$' <<<"${gateway_missing_readiness_render}"
[[ "$(
  render_component_hash gateway \
    --set-json components.gateway.readinessProbe=null
)" == "${gateway_default_hash}" ]]

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
