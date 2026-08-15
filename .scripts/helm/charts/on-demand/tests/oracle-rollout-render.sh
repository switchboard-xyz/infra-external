#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chart_dir="$(readlink -f "${script_dir}/..")"
cfg_dir="$(readlink -f "${chart_dir}/../../cfg")"
oracle_image="docker.io/switchboardlabs/oracle"
devnet_digest="sha256:c53c7fdefb4e9632cb1877e0792abab7750106897336cf7bdf530c2a5770aa88"
mainnet_digest="sha256:5b4ac97eaad16f81d181ec458324fad5cbe51a7aafff35e926f083610677446b"

render_network() {
  local network="$1"
  helm template "oracle-rollout-${network}" "${chart_dir}" \
    -f "${cfg_dir}/${network}-solana-values.yaml" \
    --set-string components.oracle.image="${oracle_image}"
}

devnet_render="$(render_network devnet)"
mainnet_render="$(render_network mainnet)"
stopped_mainnet_render="$(
  helm template oracle-rollout-stopped-mainnet "${chart_dir}" \
    -f "${cfg_dir}/mainnet-solana-values.yaml" \
    --set-string components.oracle.image="${oracle_image}" \
    --set components.oracle.replicas=0
)"

grep -q "image: \"${oracle_image}@${devnet_digest}\"" <<<"${devnet_render}"
grep -q "image: \"${oracle_image}@${mainnet_digest}\"" <<<"${mainnet_render}"
grep -q '^  replicas: 0$' <<<"${stopped_mainnet_render}"

for render in "${devnet_render}" "${mainnet_render}"; do
  grep -q 'name: SUI_MAINNET_RPC' <<<"${render}"
  grep -q 'name: "task-runner-rpc"' <<<"${render}"
  grep -q 'key: "SUI_MAINNET_RPC"' <<<"${render}"
  grep -q 'name: PAYER_SECRET' <<<"${render}"
  grep -q 'name: payer-secret' <<<"${render}"
  grep -q 'image: "__GUARDIAN_DOCKER_IMAGE__:' <<<"${render}"
  grep -q 'image: "__GATEWAY_DOCKER_IMAGE__:' <<<"${render}"
  [[ "$(grep -c '^kind: Deployment$' <<<"${render}")" -eq 3 ]]
done

printf 'Oracle rollout Helm render checks passed\n'
