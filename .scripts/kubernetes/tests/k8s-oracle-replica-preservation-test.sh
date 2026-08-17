#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_rollout="$(readlink -f "${script_dir}/../k8s-oracle-rollout.sh")"
test_tmp="$(mktemp -d /tmp/oracle-replica-preservation.XXXXXX)"
fixture_root="${test_tmp}/fixture"
fake_phase="${test_tmp}/phase"
fake_helm_args="${test_tmp}/helm-args"
fake_policy_marker="${test_tmp}/policy-invoked"
fake_kubectl_non_get_marker="${test_tmp}/kubectl-non-get"

cleanup() {
  rm -rf -- "${test_tmp}"
}
trap cleanup EXIT

mkdir -p \
  "${fixture_root}/.scripts/kubernetes" \
  "${fixture_root}/.scripts/helm/cfg" \
  "${fixture_root}/.scripts/helm/charts/on-demand" \
  "${fixture_root}/cfg"
cp "${source_rollout}" "${fixture_root}/.scripts/kubernetes/k8s-oracle-rollout.sh"

target_digest='sha256:1226edf1b851fe8460ec976eeb2ff809f4c1fec271603f421f04be10356a6579'
baseline_oracle_digest="sha256:$(printf 'a%.0s' {1..64})"
guardian_digest="sha256:$(printf 'd%.0s' {1..64})"
gateway_digest="sha256:$(printf 'e%.0s' {1..64})"

cat >"${fixture_root}/.scripts/helm/cfg/devnet-solana-values.yaml" <<YAML
components:
    oracle:
      imageDigest: "${target_digest}"
YAML
cat >"${fixture_root}/cfg/00-common-vars.cfg" <<'CFG'
# Intentionally empty synthetic common configuration.
CFG
cat >"${fixture_root}/cfg/00-devnet-vars.cfg" <<'CFG'
NETWORK="devnet"
NAMESPACE="switchboard-oracle-devnet"
CFG
cat >"${fixture_root}/.scripts/kubernetes/k8s-oracle-agent-policy.py" <<'PYTHON'
import os
import sys
from pathlib import Path

Path(os.environ["FAKE_POLICY_MARKER"]).write_text("invoked")
sys.stdout.write(sys.stdin.read())
PYTHON

helm() {
  case "${1:-}" in
    status)
      return 0
      ;;
    upgrade)
      printf '%s\n' "$@" >"${FAKE_HELM_ARGS}"
      printf 'target' >"${FAKE_PHASE}"
      ;;
    *)
      printf 'unexpected fake helm command: %s\n' "${1:-}" >&2
      return 1
      ;;
  esac
}

kubectl() {
  [[ "$1" == '-n' ]]
  shift 2
  if [[ "$1" == 'rollout' ]]; then
    printf '%s\n' "$*" >"${FAKE_KUBECTL_NON_GET_MARKER}"
    return 0
  fi
  [[ "$1" == 'get' && "$2" == 'deployment' ]]
  deployment="$3"
  if [[ "$#" -eq 3 ]]; then
    return 0
  fi
  jsonpath="${5#jsonpath=}"
  phase="$(<"${FAKE_PHASE}")"

  case "${deployment}|${jsonpath}" in
    'oracle|{.spec.replicas}') printf '%s' "${FAKE_ORACLE_REPLICAS}" ;;
    'oracle|{.spec.template.spec.containers[0].image}')
      if [[ "${phase}" == 'target' ]]; then
        printf '%s' "${FAKE_TARGET_IMAGE}"
      else
        printf '%s' "${FAKE_BASELINE_ORACLE_IMAGE}"
      fi
      ;;
    'guardian|{.spec.replicas}') printf '%s' "${FAKE_GUARDIAN_REPLICAS}" ;;
    'guardian|{.spec.template.spec.containers[0].image}') printf '%s' "${FAKE_GUARDIAN_IMAGE}" ;;
    'gateway|{.spec.replicas}') printf '%s' "${FAKE_GATEWAY_REPLICAS}" ;;
    'gateway|{.spec.template.spec.containers[0].image}') printf '%s' "${FAKE_GATEWAY_IMAGE}" ;;
    'oracle|{range .spec.template.spec.containers[0].env[?(@.name=="PAYER_SECRET")]}{.valueFrom.secretKeyRef.name}/{.valueFrom.secretKeyRef.key}{end}')
      printf 'payer-secret/SOLANA_KEY'
      ;;
    'oracle|{range .spec.template.spec.containers[0].env[?(@.name=="SUI_MAINNET_RPC")]}{.valueFrom.secretKeyRef.name}/{.valueFrom.secretKeyRef.key}{end}')
      printf 'task-runner-rpc/SUI_MAINNET_RPC'
      ;;
    *'|{.spec.template.metadata.annotations.io\.katacontainers\.config\.runtime\.cc_init_data}')
      printf '%s-policy' "${deployment}"
      ;;
    *)
      printf 'unexpected fake kubectl field: %s %s\n' "${deployment}" "${jsonpath}" >&2
      return 1
      ;;
  esac
}
export -f helm kubectl

run_fixture() {
  local oracle_replicas="$1"
  local guardian_replicas="$2"
  local gateway_replicas="$3"

  env \
    FAKE_PHASE="${fake_phase}" \
    FAKE_HELM_ARGS="${fake_helm_args}" \
    FAKE_POLICY_MARKER="${fake_policy_marker}" \
    FAKE_KUBECTL_NON_GET_MARKER="${fake_kubectl_non_get_marker}" \
    FAKE_BASELINE_ORACLE_IMAGE="docker.io/switchboardlabs/oracle@${baseline_oracle_digest}" \
    FAKE_TARGET_IMAGE="docker.io/switchboardlabs/oracle@${target_digest}" \
    FAKE_ORACLE_REPLICAS="${oracle_replicas}" \
    FAKE_GUARDIAN_IMAGE="docker.io/switchboardlabs/guardian@${guardian_digest}" \
    FAKE_GUARDIAN_REPLICAS="${guardian_replicas}" \
    FAKE_GATEWAY_IMAGE="docker.io/switchboardlabs/gateway@${gateway_digest}" \
    FAKE_GATEWAY_REPLICAS="${gateway_replicas}" \
    bash "${fixture_root}/.scripts/kubernetes/k8s-oracle-rollout.sh" devnet
}

printf 'baseline' >"${fake_phase}"
run_fixture 1 0 1 >/dev/null
grep -Fxq 'components.oracle.replicas=1' "${fake_helm_args}"
grep -Fxq 'components.guardian.replicas=0' "${fake_helm_args}"
grep -Fxq 'components.gateway.replicas=1' "${fake_helm_args}"

printf 'baseline' >"${fake_phase}"
run_fixture 1 1 0 >/dev/null
grep -Fxq 'components.oracle.replicas=1' "${fake_helm_args}"
grep -Fxq 'components.guardian.replicas=1' "${fake_helm_args}"
grep -Fxq 'components.gateway.replicas=0' "${fake_helm_args}"

printf 'baseline' >"${fake_phase}"
: >"${fake_helm_args}"
: >"${fake_policy_marker}"
: >"${fake_kubectl_non_get_marker}"
oracle_zero_error="${test_tmp}/oracle-zero-error"
if run_fixture 0 1 1 >"${test_tmp}/oracle-zero-output" 2>"${oracle_zero_error}"; then
  printf 'stopped Oracle was accepted for rollout\n' >&2
  exit 1
fi
grep -Fxq 'Stopped Oracle is excluded from rollout selection; dormant desired state was not rewritten' "${oracle_zero_error}"
[[ ! -s "${fake_helm_args}" ]]
[[ ! -s "${fake_policy_marker}" ]]
[[ ! -s "${fake_kubectl_non_get_marker}" ]]

printf 'baseline' >"${fake_phase}"
: >"${fake_helm_args}"
if run_fixture 1 __absent__ 1 >/dev/null 2>&1; then
  printf 'invalid Guardian replica state was accepted\n' >&2
  exit 1
fi
[[ ! -s "${fake_helm_args}" ]]

printf 'baseline' >"${fake_phase}"
: >"${fake_helm_args}"
if run_fixture 1 1 __absent__ >/dev/null 2>&1; then
  printf 'invalid Gateway replica state was accepted\n' >&2
  exit 1
fi
[[ ! -s "${fake_helm_args}" ]]

printf 'Oracle rollout replica-preservation checks passed\n'
