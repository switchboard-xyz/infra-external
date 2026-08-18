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
mainnet_default_hash="bf555d3e30cdee6e8425a8ac12c980bf0af49be1efa6b9ea793861e536b680d6"
oracle_default_hash="d15ffa5a43940a55074cf6ae3818ff050dcfcdc5bcc9a1f86997816f2989e66a"
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
