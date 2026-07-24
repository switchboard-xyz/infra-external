#!/usr/bin/env bash
set -Eeuo pipefail

cluster="${1:-devnet}"
if [[ $# -eq 0 ]]; then
  printf "No cluster specified, using default: 'devnet'\n"
fi
if [[ "${cluster}" != "devnet" && "${cluster}" != "mainnet" ]]; then
  printf "Only valid cluster values are 'devnet' and 'mainnet'.\n" >&2
  exit 1
fi

export GUARDIAN_ENABLED="${GUARDIAN_ENABLED:-true}"
export GUARDIAN_IMAGE_DIGEST="${GUARDIAN_IMAGE_DIGEST:-}"
export GUARDIAN_REMEDIATOR_ENABLED="${GUARDIAN_REMEDIATOR_ENABLED:-false}"
export GUARDIAN_EPHEMERAL_STORAGE_ENABLED="${GUARDIAN_EPHEMERAL_STORAGE_ENABLED:-false}"
export GUARDIAN_PUBLIC_RPC_FALLBACK_ENABLED="${GUARDIAN_PUBLIC_RPC_FALLBACK_ENABLED:-true}"
export JUPITER_SWAP_API_KEY_SECRET_NAME="${JUPITER_SWAP_API_KEY_SECRET_NAME:-jupiter-swap-api}"
export JUPITER_SWAP_API_KEY_SECRET_KEY="${JUPITER_SWAP_API_KEY_SECRET_KEY:-api-key}"
export PAGERDUTY_SECRET_NAME="${PAGERDUTY_SECRET_NAME:-guardian-pagerduty}"
export PAGERDUTY_SECRET_KEY="${PAGERDUTY_SECRET_KEY:-routing-key}"

export DEVNET_DOCKER_IMAGE_TAG="${DEVNET_DOCKER_IMAGE_TAG:-devnet}"
export MAINNET_DOCKER_IMAGE_TAG="${MAINNET_DOCKER_IMAGE_TAG:-stable}"
export V2_DOCKER_IMAGE_TAG="${V2_DOCKER_IMAGE_TAG:-v2-on-v3}"
export ORACLE_DOCKER_IMAGE="${ORACLE_DOCKER_IMAGE:-docker.io/switchboardlabs/oracle}"
export GUARDIAN_DOCKER_IMAGE="${GUARDIAN_DOCKER_IMAGE:-docker.io/switchboardlabs/guardian}"
export GATEWAY_DOCKER_IMAGE="${GATEWAY_DOCKER_IMAGE:-docker.io/switchboardlabs/gateway}"
export OTLP_ENDPOINT="${OTLP_ENDPOINT:-http://sb-log-forwarding-alloy.sb-log-forwarding.svc.cluster.local:4317}"

if [[ "${cluster}" == "devnet" ]]; then
  public_heartbeat_fallback="https://api.devnet.solana.com"
else
  public_heartbeat_fallback="https://api.mainnet-beta.solana.com"
fi
if [[ "${GUARDIAN_PUBLIC_RPC_FALLBACK_ENABLED}" == "true" ]]; then
  heartbeat_rpc_fallback_urls="${public_heartbeat_fallback}"
elif [[ "${GUARDIAN_PUBLIC_RPC_FALLBACK_ENABLED}" == "false" ]]; then
  heartbeat_rpc_fallback_urls=""
else
  printf "GUARDIAN_PUBLIC_RPC_FALLBACK_ENABLED must be true or false\n" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "${script_dir}/../.." && pwd)"
cfg_dir="${repo_dir}/cfg"
cfg_common_file="${cfg_dir}/00-common-vars.cfg"
cfg_cluster_file="${cfg_dir}/00-${cluster}-vars.cfg"
helm_dir="${repo_dir}/.scripts/helm"
helm_on_demand_chart_dir="${helm_dir}/charts/on-demand"
helm_landing_page_chart_dir="${helm_dir}/charts/oracle-landing-page"
helm_values_file="${helm_dir}/cfg/${cluster}-solana-values.yaml"
helm_landing_values_file="${helm_dir}/cfg/oracle-landing-page-values.yaml"
tmp_dir="$(mktemp -d)"
tmp_helm_file="${tmp_dir}/helm-values.yaml"
landing_tmp_helm_file="${tmp_dir}/landing-values.yaml"

cleanup() {
  rm -f "${tmp_helm_file}" "${landing_tmp_helm_file}"
  rmdir "${tmp_dir}" 2>/dev/null || true
}
trap cleanup EXIT

fail() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

check_repo_drift() {
  local changes upstream local_head upstream_head
  changes="$(git -C "${repo_dir}" status --porcelain --untracked-files=all)"
  [[ -z "${changes}" ]] || fail "repository has machine-local drift; refusing to deploy"

  upstream="$(git -C "${repo_dir}" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)"
  if [[ -n "${upstream}" ]]; then
    local_head="$(git -C "${repo_dir}" rev-parse HEAD)"
    upstream_head="$(git -C "${repo_dir}" rev-parse "${upstream}")"
    [[ "${local_head}" == "${upstream_head}" ]] ||
      fail "repository is not at its recorded upstream commit; update by fast-forward only"
  fi
}

check_cluster_access() {
  local context
  context="$(kubectl config current-context)"
  [[ -n "${context}" ]] || fail "kubectl has no current context"
  kubectl cluster-info >/dev/null
  kubectl auth can-i get pods --all-namespaces | grep -qx "yes" ||
    fail "current Kubernetes identity cannot inspect pods"
  kubectl auth can-i patch deployments.apps -n "${NAMESPACE}" | grep -qx "yes" ||
    fail "current Kubernetes identity cannot patch Deployments in ${NAMESPACE}"
}

ensure_namespace() {
  if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    printf "KUBECTL: creating namespace %s\n" "${NAMESPACE}"
    kubectl create namespace "${NAMESPACE}"
  fi
}

ensure_payer_secret() {
  [[ -n "${PAYER_SECRET_KEY:-}" ]] || return 0
  local payer_file="${repo_dir}/data/${cluster}_payer.json"
  [[ -r "${payer_file}" ]] || fail "payer key file is missing or unreadable"
  kubectl -n "${NAMESPACE}" create secret generic payer-secret \
    --from-file="${PAYER_SECRET_KEY}=${payer_file}" \
    --dry-run=client -o yaml |
    kubectl apply -f -
  kubectl -n "${NAMESPACE}" get secret payer-secret \
    -o "jsonpath={.data.${PAYER_SECRET_KEY}}" |
    grep -q . || fail "payer-secret does not contain the configured key"
}

ensure_jupiter_secret() {
  if [[ -n "${JUPITER_SWAP_API_KEY_FILE:-}" ]]; then
    [[ -r "${JUPITER_SWAP_API_KEY_FILE}" ]] ||
      fail "JUPITER_SWAP_API_KEY_FILE is unreadable"
    kubectl -n "${NAMESPACE}" create secret generic \
      "${JUPITER_SWAP_API_KEY_SECRET_NAME}" \
      --from-file="${JUPITER_SWAP_API_KEY_SECRET_KEY}=${JUPITER_SWAP_API_KEY_FILE}" \
      --dry-run=client -o yaml |
      kubectl apply -f -
  elif ! kubectl -n "${NAMESPACE}" get secret "${JUPITER_SWAP_API_KEY_SECRET_NAME}" \
    >/dev/null 2>&1; then
    fail "${JUPITER_SWAP_API_KEY_SECRET_NAME} is missing; set JUPITER_SWAP_API_KEY_FILE to a replacement credential file"
  fi
  kubectl -n "${NAMESPACE}" get secret "${JUPITER_SWAP_API_KEY_SECRET_NAME}" \
    -o "jsonpath={.data.${JUPITER_SWAP_API_KEY_SECRET_KEY}}" |
    grep -q . || fail "Jupiter API Secret does not contain the configured key"
}

ensure_pagerduty_secret() {
  [[ "${GUARDIAN_ENABLED}" == "true" ]] || return 0
  if [[ -n "${PAGERDUTY_ROUTING_KEY_FILE:-}" ]]; then
    [[ -r "${PAGERDUTY_ROUTING_KEY_FILE}" ]] ||
      fail "PAGERDUTY_ROUTING_KEY_FILE is unreadable"
    kubectl -n "${NAMESPACE}" create secret generic \
      "${PAGERDUTY_SECRET_NAME}" \
      --from-file="${PAGERDUTY_SECRET_KEY}=${PAGERDUTY_ROUTING_KEY_FILE}" \
      --dry-run=client -o yaml |
      kubectl apply -f -
  elif ! kubectl -n "${NAMESPACE}" get secret "${PAGERDUTY_SECRET_NAME}" \
    >/dev/null 2>&1; then
    fail "${PAGERDUTY_SECRET_NAME} is missing; set PAGERDUTY_ROUTING_KEY_FILE to provision it"
  fi
  kubectl -n "${NAMESPACE}" get secret "${PAGERDUTY_SECRET_NAME}" \
    -o "jsonpath={.data.${PAGERDUTY_SECRET_KEY}}" |
    grep -q . || fail "PagerDuty Secret does not contain the configured key"
}

check_guardian_release_safety() {
  [[ "${GUARDIAN_ENABLED}" == "true" ]] || return 0
  [[ "${GUARDIAN_IMAGE_DIGEST}" =~ ^sha256:[a-f0-9]{64}$ ]] ||
    fail "GUARDIAN_IMAGE_DIGEST must be an immutable sha256 digest"

  local primary fallback primary_authority fallback_authority
  primary="${RPC_URL%/}"
  if [[ "${GUARDIAN_PUBLIC_RPC_FALLBACK_ENABLED}" == "true" ]]; then
    fallback="${public_heartbeat_fallback}"
    primary_authority="${primary#*://}"
    primary_authority="${primary_authority%%/*}"
    primary_authority="${primary_authority##*@}"
    primary_authority="${primary_authority%%:*}"
    primary_authority="${primary_authority,,}"
    fallback_authority="${fallback#*://}"
    fallback_authority="${fallback_authority%%/*}"
    fallback_authority="${fallback_authority%%:*}"
    fallback_authority="${fallback_authority,,}"
    [[ "${primary}" != "${fallback}" && "${primary_authority}" != "${fallback_authority}" ]] ||
      fail "guardian primary RPC must differ from the public heartbeat fallback"
  fi

  if [[ "${GUARDIAN_REMEDIATOR_ENABLED}" == "true" ]]; then
    kubectl auth can-i patch deployment/guardian -n "${NAMESPACE}" | grep -qx "yes" ||
      fail "current Kubernetes identity cannot patch deployment/guardian"
  fi
}

run_fleet_health_gate() {
  [[ "${GUARDIAN_ENABLED}" == "true" ]] || return 0
  local checker="${GUARDIAN_FLEET_HEALTH_COMMAND:-${script_dir}/guardian-fleet-health.sh}"
  [[ -x "${checker}" ]] ||
    fail "GUARDIAN_FLEET_HEALTH_COMMAND must name an executable health checker"
  local healthy
  healthy="$("${checker}")"
  [[ "${healthy}" =~ ^[0-9]+$ ]] || fail "fleet health checker did not return an integer"
  ((healthy >= 5)) || fail "only ${healthy} fleet-healthy guardians; at least 5 are required"
}

check_repo_drift

# shellcheck source=/dev/null
source "${cfg_common_file}"
# shellcheck source=/dev/null
source "${cfg_cluster_file}"

cp "${helm_values_file}" "${tmp_helm_file}"
cp "${helm_landing_values_file}" "${landing_tmp_helm_file}"

# shellcheck source=/dev/null
source "${repo_dir}/.scripts/var/_load_vars.sh"
set +u
load_vars "${tmp_helm_file}"
load_vars "${landing_tmp_helm_file}"
set -u

check_cluster_access
ensure_namespace
ensure_payer_secret
ensure_jupiter_secret
ensure_pagerduty_secret
check_guardian_release_safety
run_fleet_health_gate

helm lint "${helm_on_demand_chart_dir}" -f "${tmp_helm_file}" \
  --set-string "heartbeatRpcFallbackUrls=${heartbeat_rpc_fallback_urls}" \
  --set-string "components.guardian.imageDigest=${GUARDIAN_IMAGE_DIGEST}" \
  --set "components.guardian.remediator.enabled=${GUARDIAN_REMEDIATOR_ENABLED}" \
  --set "components.guardian.ephemeralStorage.enabled=${GUARDIAN_EPHEMERAL_STORAGE_ENABLED}"

printf "HELM: installing Switchboard Oracle under namespace %s\n" "${NAMESPACE}"
helm upgrade --install "sb-oracle-${NETWORK}" \
  -n "${NAMESPACE}" --create-namespace \
  -f "${tmp_helm_file}" \
  --set-string "heartbeatRpcFallbackUrls=${heartbeat_rpc_fallback_urls}" \
  --set-string "tracing.otlpEndpoint=${OTLP_ENDPOINT}" \
  --set-string "components.docker_image_tag=${DOCKER_IMAGE_TAG}" \
  --set "components.oracle.enabled=${ORACLE_ENABLED}" \
  --set-string "components.oracle.image=${ORACLE_DOCKER_IMAGE}" \
  --set "components.guardian.enabled=${GUARDIAN_ENABLED}" \
  --set-string "components.guardian.image=${GUARDIAN_DOCKER_IMAGE}" \
  --set-string "components.guardian.imageDigest=${GUARDIAN_IMAGE_DIGEST}" \
  --set "components.guardian.remediator.enabled=${GUARDIAN_REMEDIATOR_ENABLED}" \
  --set "components.guardian.ephemeralStorage.enabled=${GUARDIAN_EPHEMERAL_STORAGE_ENABLED}" \
  --set "components.gateway.enabled=${GATEWAY_ENABLED}" \
  --set-string "components.gateway.image=${GATEWAY_DOCKER_IMAGE}" \
  --set-string "jupiterSwapApiKeySecret.name=${JUPITER_SWAP_API_KEY_SECRET_NAME}" \
  --set-string "jupiterSwapApiKeySecret.key=${JUPITER_SWAP_API_KEY_SECRET_KEY}" \
  --set-string "pagerDutySecret.name=${PAGERDUTY_SECRET_NAME}" \
  --set-string "pagerDutySecret.key=${PAGERDUTY_SECRET_KEY}" \
  --atomic --wait --timeout 10m \
  "${helm_on_demand_chart_dir}"
printf "HELM: Switchboard Oracle installed under namespace %s\n" "${NAMESPACE}"

if [[ "${GUARDIAN_ENABLED}" == "true" ]]; then
  kubectl rollout status deployment/guardian -n "${NAMESPACE}" --timeout=10m
  run_fleet_health_gate
fi

if [[ "${LANDING_ENABLED:-}" == "true" ]]; then
  printf "HELM: installing Switchboard landing page under namespace %s\n" "${LANDING_NAMESPACE}"
  helm upgrade --install oracle-landing-page \
    -n "${LANDING_NAMESPACE}" --create-namespace \
    -f "${landing_tmp_helm_file}" \
    --set-string "oracle_landing_page.namespace=${LANDING_NAMESPACE}" \
    --set-string "oracle_landing_page.image=${LANDING_IMAGE}" \
    --set-string "oracle_landing_page.image_tag=${LANDING_IMAGE_TAG}" \
    --set-string "oracle_landing_page.ingress.host=${CLUSTER_DOMAIN}" \
    --set "guardian.devnet.enabled=${GUARDIAN_ENABLED}" \
    --set "guardian.mainnet.enabled=${GUARDIAN_ENABLED}" \
    --set "oracle.devnet.enabled=${ORACLE_ENABLED}" \
    --set "oracle.mainnet.enabled=${ORACLE_ENABLED}" \
    --atomic --wait --timeout 10m \
    "${helm_landing_page_chart_dir}"
  printf "HELM: Switchboard landing page installed under namespace %s\n" "${LANDING_NAMESPACE}"
fi
