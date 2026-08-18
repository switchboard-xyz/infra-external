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

gateway_default_hash="0ef9255df165c2340ea5c6ec7e40a47504a225680ff8fbb8dae874329a0caaaf"
mainnet_default_hash="726bd992e884f9ab63b9298ca4f0a176d26c6a843894569089f506935af1bdba"
oracle_default_hash="8013155a382e1af58da2a4bd0d7c7057d081c30ec17bda6c9828edaad9e1b7a9"
guardian_default_hash="e95244187cad2bc596539652f33fcd16c384d9d923b3da5aaba107ebbe60b9b8"

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
