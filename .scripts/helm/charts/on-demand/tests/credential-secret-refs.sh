#!/usr/bin/env bash
set -Eeuo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rendered="$(mktemp)"
trap 'rm -f "${rendered}"' EXIT

helm lint "${chart_dir}"
helm template credential-test "${chart_dir}" >"${rendered}"

for component in oracle guardian gateway; do
  rg -q "name: ${component}" "${rendered}"
done
if rg -U -q 'name: (JUPITER_SWAP_API_KEY|PAYER_SECRET)\n[[:space:]]+value:' "${rendered}"; then
  printf "a credential environment variable rendered as plaintext\n" >&2
  exit 1
fi
if rg -n '^jupiterSwapApiKey:' "${chart_dir}" "$(dirname "${chart_dir}")/../cfg"; then
  printf "a plaintext Jupiter credential field remains in Helm source\n" >&2
  exit 1
fi
[[ "$(rg -c 'name: "jupiter-swap-api"' "${rendered}")" -eq 3 ]] || {
  printf "not every workload references the Jupiter Kubernetes Secret\n" >&2
  exit 1
}
[[ "$(rg -c 'name: payer-secret' "${rendered}")" -eq 3 ]] || {
  printf "not every workload references the payer Kubernetes Secret\n" >&2
  exit 1
}

printf "credential Secret reference assertions passed\n"
