#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chart_dir="$(readlink -f "${script_dir}/..")"
digest="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

oracle_digest_render="$(
  helm template task-runner-rpc "${chart_dir}" \
    --show-only templates/oracle.yaml \
    --set-string taskRunnerRpc.secretName=task-runner-rpc \
    --set-string taskRunnerRpc.suiMainnetRpcKey=SUI_MAINNET_RPC \
    --set-string components.oracle.imageDigest="${digest}"
)"

grep -q 'image: "docker.io/switchboardlabs/oracle@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' \
  <<<"${oracle_digest_render}"
grep -q 'name: SUI_MAINNET_RPC' <<<"${oracle_digest_render}"
grep -q 'secretKeyRef:' <<<"${oracle_digest_render}"
grep -q 'name: "task-runner-rpc"' <<<"${oracle_digest_render}"
grep -q 'key: "SUI_MAINNET_RPC"' <<<"${oracle_digest_render}"
[[ "$(grep -c 'name: SUI_MAINNET_RPC' <<<"${oracle_digest_render}")" -eq 1 ]]

oracle_default_render="$(
  helm template task-runner-rpc "${chart_dir}" \
    --show-only templates/oracle.yaml
)"
! grep -q 'SUI_MAINNET_RPC' <<<"${oracle_default_render}"
! grep -q 'CANDLE_COLLECTION_ENABLED' <<<"${oracle_default_render}"
! grep -q '^        envFrom:$' <<<"${oracle_default_render}"

oracle_environment_render="$(
  helm template task-runner-rpc "${chart_dir}" \
    --show-only templates/oracle.yaml \
    --set components.oracle.candleCollection.enabled=true \
    --set-string components.oracle.candleCollection.value=enabled \
    --set components.oracle.environmentSecret.enabled=true \
    --set-string components.oracle.environmentSecret.name=oracle-environment \
    --set components.oracle.environmentSecret.optionalSet=true \
    --set components.oracle.environmentSecret.optional=true \
    --set-string taskRunnerRpc.secretName=task-runner-rpc \
    --set-string taskRunnerRpc.suiMainnetRpcKey=SUI_MAINNET_RPC
)"
grep -q 'name: CANDLE_COLLECTION_ENABLED' <<<"${oracle_environment_render}"
grep -q 'value: "enabled"' <<<"${oracle_environment_render}"
grep -q '^        envFrom:$' <<<"${oracle_environment_render}"
grep -q 'name: "oracle-environment"' <<<"${oracle_environment_render}"
grep -q 'optional: true' <<<"${oracle_environment_render}"
otlp_line="$(grep -n 'name: OTLP_ENDPOINT' <<<"${oracle_environment_render}" | cut -d: -f1)"
candle_line="$(grep -n 'name: CANDLE_COLLECTION_ENABLED' <<<"${oracle_environment_render}" | cut -d: -f1)"
sui_line="$(grep -n 'name: SUI_MAINNET_RPC' <<<"${oracle_environment_render}" | cut -d: -f1)"
[[ "${otlp_line}" -lt "${candle_line}" ]]
[[ "${candle_line}" -lt "${sui_line}" ]]

guardian_render="$(
  helm template task-runner-rpc "${chart_dir}" \
    --show-only templates/guardian.yaml \
    --set-string taskRunnerRpc.secretName=task-runner-rpc
)"
gateway_render="$(
  helm template task-runner-rpc "${chart_dir}" \
    --show-only templates/gateway.yaml \
    --set-string taskRunnerRpc.secretName=task-runner-rpc
)"
! grep -q 'SUI_MAINNET_RPC' <<<"${guardian_render}"
! grep -q 'SUI_MAINNET_RPC' <<<"${gateway_render}"

numeric_resource_render="$(
  helm template task-runner-rpc "${chart_dir}" \
    --set-string components.oracle.resources.limits.cpu=4 \
    --set-string components.guardian.resources.limits.cpu=4 \
    --set-string components.gateway.resources.limits.cpu=4
)"
[[ "$(grep -c 'cpu: "4"' <<<"${numeric_resource_render}")" -eq 3 ]]

oracle_tag_render="$(
  helm template task-runner-rpc "${chart_dir}" \
    --show-only templates/oracle.yaml \
    --set-string components.docker_image_tag=stable
)"
grep -q 'image: "docker.io/switchboardlabs/oracle:stable"' <<<"${oracle_tag_render}"

oracle_cluster_render="$(
  helm template task-runner-rpc "${chart_dir}" \
    --show-only templates/oracle.yaml \
    --set-string cluster=devnet
)"
[[ "$(grep -c 'cluster: "devnet"' <<<"${oracle_cluster_render}")" -eq 2 ]]

if helm template task-runner-rpc "${chart_dir}" \
  --show-only templates/oracle.yaml \
  --set-string taskRunnerRpc.secretName=task-runner-rpc \
  --set-string taskRunnerRpc.suiMainnetRpcKey= >/dev/null 2>&1; then
  printf "expected a configured Secret without a key to fail rendering\n" >&2
  exit 1
fi

if helm template task-runner-rpc "${chart_dir}" \
  --show-only templates/oracle.yaml \
  --set components.oracle.environmentSecret.enabled=true \
  --set-string components.oracle.environmentSecret.name= >/dev/null 2>&1; then
  printf "expected an enabled Oracle environment Secret without a name to fail rendering\n" >&2
  exit 1
fi

if helm template task-runner-rpc "${chart_dir}" \
  --show-only templates/oracle.yaml \
  --set-string components.oracle.imageDigest=latest >/dev/null 2>&1; then
  printf "expected an invalid oracle digest to fail rendering\n" >&2
  exit 1
fi

printf "task-runner RPC Helm render checks passed\n"
