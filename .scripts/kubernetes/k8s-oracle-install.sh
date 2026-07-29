#!/usr/bin/env bash
set -euo pipefail

cluster="${1:-devnet}"

set +u
if [[ -z "${1}" ]]; then
  printf "No cluster specified, using default: 'devnet'\n"
fi
set -u

if [[ "${cluster}" != "devnet" &&
  "${cluster}" != "mainnet" ]]; then
  printf "Only valid cluster values are 'devnet' and 'mainnet'.\n"
  exit 1
fi

export GUARDIAN_ENABLED="true"

# defaults - these variables can be changed via `cfg/` files
export DEVNET_DOCKER_IMAGE_TAG="devnet"
export MAINNET_DOCKER_IMAGE_TAG="stable"
export V2_DOCKER_IMAGE_TAG="v2-on-v3"
export ORACLE_DOCKER_IMAGE="docker.io/switchboardlabs/oracle"
export GUARDIAN_DOCKER_IMAGE="docker.io/switchboardlabs/guardian"
export GATEWAY_DOCKER_IMAGE="docker.io/switchboardlabs/gateway"
export OTLP_ENDPOINT="http://sb-log-forwarding-alloy.sb-log-forwarding.svc.cluster.local:4317"

repo_dir="$(readlink -f ../../..)"

cfg_dir="${repo_dir}/cfg"
cfg_common_file="${cfg_dir}/00-common-vars.cfg"
cfg_cluster_file="${cfg_dir}/00-${cluster}-vars.cfg"

# import vars
source "${cfg_common_file}"
source "${cfg_cluster_file}"

printf "\n"
printf "==========================================================================\n"
printf "\n"

if [[ "$(kubectl get ns | grep -e '^'${NAMESPACE}'\W')" == "" ]]; then
  printf "KUBECTL: creating Namespace ${NAMESPACE}\n"
  kubectl create namespace "${NAMESPACE}"
  printf "KUBECTL: Namespace ${NAMESPACE} created\n"
fi

helm_dir="${repo_dir}/.scripts/helm/"
helm_charts_dir="${helm_dir}/charts/"
helm_on_demand_chart_dir="${helm_charts_dir}/on-demand/"
helm_landing_page_chart_dir="${helm_charts_dir}/oracle-landing-page/"
helm_values_file="${helm_dir}/cfg/${cluster}-solana-values.yaml"
helm_landing_values_file="${helm_dir}/cfg/oracle-landing-page-values.yaml"
tmp_helm_file="/tmp/helm_values.yaml"
landing_tmp_helm_file="/tmp/helm_landing_values.yaml"

cp "${helm_values_file}" "${tmp_helm_file}"
cp "${helm_landing_values_file}" "${landing_tmp_helm_file}"

source "${repo_dir}"/.scripts/var/_load_vars.sh
set +u
load_vars "${tmp_helm_file}" >/dev/null 2>&1
load_vars "${landing_tmp_helm_file}" >/dev/null 2>&1

sgx_data_dir="${repo_dir}/data/${cluster}_protected_files"
task_runner_sui_rpc_file="${sgx_data_dir}/${TASK_RUNNER_SUI_RPC_PROTECTED_FILE}"

if [[ "${ORACLE_ENABLED}" == "true" && -n "${TASK_RUNNER_RPC_SECRET_NAME}" ]]; then
  if [[ -z "${TASK_RUNNER_SUI_RPC_SECRET_KEY}" ||
    -z "${TASK_RUNNER_SUI_RPC_PROTECTED_FILE}" ]]; then
    printf "ERROR: task-runner RPC Secret key and protected filename are required\n" >&2
    exit 1
  fi

  if [[ ! -f "${task_runner_sui_rpc_file}" ]]; then
    printf "ERROR: missing protected Sui RPC file for %s\n" "${cluster}" >&2
    exit 1
  fi

  if [[ ! -s "${task_runner_sui_rpc_file}" ]]; then
    printf "ERROR: protected Sui RPC file for %s is empty\n" "${cluster}" >&2
    exit 1
  fi

  if [[ "$(stat -c '%a' "${task_runner_sui_rpc_file}")" != "600" ]]; then
    printf "ERROR: protected Sui RPC file for %s must have mode 0600\n" "${cluster}" >&2
    exit 1
  fi

  if [[ "$(wc -l < "${task_runner_sui_rpc_file}")" -ne 0 ]] ||
    LC_ALL=C grep -q $'\r' "${task_runner_sui_rpc_file}"; then
    printf "ERROR: protected Sui RPC file for %s must not contain a newline\n" "${cluster}" >&2
    exit 1
  fi

  if [[ "$(head -c 8 "${task_runner_sui_rpc_file}")" != http://* &&
    "$(head -c 9 "${task_runner_sui_rpc_file}")" != https://* ]]; then
    printf "ERROR: protected Sui RPC file for %s must contain an HTTP(S) URL\n" "${cluster}" >&2
    exit 1
  fi

  printf "KUBECTL: reconciling %s/%s\n" "${NAMESPACE}" "${TASK_RUNNER_RPC_SECRET_NAME}"
  kubectl \
    -n "${NAMESPACE}" \
    create secret generic "${TASK_RUNNER_RPC_SECRET_NAME}" \
    --from-file="${TASK_RUNNER_SUI_RPC_SECRET_KEY}=${task_runner_sui_rpc_file}" \
    --dry-run=client \
    -o yaml |
    kubectl apply -f - >/dev/null

  if [[ "$(
    kubectl \
      -n "${NAMESPACE}" \
      get secret "${TASK_RUNNER_RPC_SECRET_NAME}" \
      --template="{{if index .data \"${TASK_RUNNER_SUI_RPC_SECRET_KEY}\"}}present{{end}}"
  )" != "present" ]]; then
    printf "ERROR: %s/%s is missing the required key\n" \
      "${NAMESPACE}" "${TASK_RUNNER_RPC_SECRET_NAME}" >&2
    exit 1
  fi
  printf "KUBECTL: %s/%s reconciled\n" "${NAMESPACE}" "${TASK_RUNNER_RPC_SECRET_NAME}"
fi

printf "HELM: Installing Switchboard Oracle under namespace ${NAMESPACE}\n"
helm upgrade -i "sb-oracle-${NETWORK}" \
  -n "${NAMESPACE}" --create-namespace \
  -f "${tmp_helm_file}" \
  --set tracing.otlpEndpoint="${OTLP_ENDPOINT}" \
  --set components.docker_image_tag="${DOCKER_IMAGE_TAG}" \
  --set components.oracle.enabled=${ORACLE_ENABLED} \
  --set components.oracle.image="${ORACLE_DOCKER_IMAGE}" \
  --set-string components.oracle.imageDigest="${ORACLE_DOCKER_IMAGE_DIGEST}" \
  --set components.guardian.enabled=${GUARDIAN_ENABLED} \
  --set components.guardian.image="${GUARDIAN_DOCKER_IMAGE}" \
  --set components.gateway.enabled=${GATEWAY_ENABLED} \
  --set components.gateway.image="${GATEWAY_DOCKER_IMAGE}" \
  "${helm_on_demand_chart_dir}" >/dev/null
printf "HELM: Switchboard Oracle installed under namespace ${NAMESPACE}\n"

if [[ "${PAYER_SECRET_KEY}" != "" ]]; then
  printf "KUBECTL: creating secret ${NAMESPACE}/payer-secret\n"
  # delete pre-existing secret
  set +e
  kubectl \
    -n "${NAMESPACE}" \
    delete secret payer-secret >/dev/null 2>&1
  set -e

  # re-create secret
  kubectl \
    -n "${NAMESPACE}" \
    create secret generic \
    --from-file="${PAYER_SECRET_KEY}=../../../data/${cluster}_payer.json" \
    payer-secret >/dev/null
  printf "KUBECTL: secret ${NAMESPACE}/payer-secret created\n"
fi

if [[ "${LANDING_ENABLED}" != "" && "${LANDING_ENABLED}" == "true" ]]; then
  printf "HELM: Installing Switchboard Landing page under namespace ${LANDING_NAMESPACE}\n"
  helm upgrade -i "oracle-landing-page" \
    -n "${LANDING_NAMESPACE}" --create-namespace \
    -f "${landing_tmp_helm_file}" \
    --set oracle_landing_page.namespace="${LANDING_NAMESPACE}" \
    --set oracle_landing_page.image="${LANDING_IMAGE}" \
    --set oracle_landing_page.image_tag="${LANDING_IMAGE_TAG}" \
    --set oracle_landing_page.ingress.host="${CLUSTER_DOMAIN}" \
    --set guardian.devnet.enabled=${GUARDIAN_ENABLED} \
    --set guardian.mainnet.enabled=${GUARDIAN_ENABLED} \
    --set oracle.devnet.enabled=${ORACLE_ENABLED} \
    --set oracle.mainnet.enabled=${ORACLE_ENABLED} \
    "${helm_landing_page_chart_dir}" >/dev/null
  printf "HELM: Switchboard Oracle Landing page installed under namespace ${LANDING_NAMESPACE}\n"
fi

rm "${tmp_helm_file}"

set -u
