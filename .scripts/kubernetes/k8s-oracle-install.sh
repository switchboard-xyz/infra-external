#!/usr/bin/env bash
set -u -e

cluster="${1:-devnet}"

if [[ "${cluster}" == "mainnet-beta" ]]; then
  cluster="mainnet"
fi

if [[ "${cluster}" != "devnet" &&
  "${cluster}" != "mainnet" &&
  "${cluster}" != "mainnet-beta" ]]; then
  echo "Only valid cluster values are 'devnet' and 'mainnet'/'mainnet-beta'."
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

repo_dir="$(readlink -f ../../..)"

cfg_dir="${repo_dir}/cfg"
cfg_common_file="${cfg_dir}/00-common-vars.cfg"
cfg_cluster_file="${cfg_dir}/00-${cluster}-vars.cfg"

# import vars
source "${cfg_common_file}"
source "${cfg_cluster_file}"

echo "===="
echo " "

if [[ "$(kubectl get ns | grep -e '^'${NAMESPACE}'\W')" == "" ]]; then
  echo "KUBECTL: creating Namespace ${NAMESPACE}"
  kubectl create namespace "${NAMESPACE}"
  echo "KUBECTL: Namespace ${NAMESPACE} created"
fi

helm_dir="${repo_dir}/.scripts/helm/charts/"
helm_on_demand_chart_dir="${helm_dir}/on-demand/"
helm_landing_page_chart_dir="${helm_dir}/landing-page/"
helm_default_values_file="${helm_chart_dir}/values.yaml"
helm_values_file="${helm_dir}/cfg/${cluster}-solana-values.yaml"
tmp_helm_file="/tmp/helm_values.yaml"

cp "${helm_values_file}" "${tmp_helm_file}"

source "${repo_dir}"/.scripts/var/_load_vars.sh
set +u
load_vars "${tmp_helm_file}" >/dev/null 2>&1

sgx_data_dir="${repo_dir}/data/${cluster}_protected_files"
if [ ! -d "${repo_dir}" ]; then
  mkdir "${repo_dir}"
fi

echo "HELM: Installing Switchboard Oracle under namespace ${NAMESPACE}"
helm upgrade -i "sb-oracle-${NETWORK}" \
  -n "${NAMESPACE}" --create-namespace \
  -f "${helm_default_values_file}" \
  -f "${tmp_helm_file}" \
  --set components.docker_image_tag="${DOCKER_IMAGE_TAG}" \
  --set components.oracle.enabled=${ORACLE_ENABLED} \
  --set components.oracle.image="${ORACLE_DOCKER_IMAGE}" \
  --set components.guardian.enabled=${GUARDIAN_ENABLED} \
  --set components.guardian.image="${GUARDIAN_DOCKER_IMAGE}" \
  --set components.gateway.enabled=${GUARDIAN_ENABLED} \
  --set components.gateway.image="${GATEWAY_DOCKER_IMAGE}" \
  "${helm_on_demand_chart_dir}" >/dev/null
echo "HELM: Switchboard Oracle installed under namespace ${NAMESPACE}"

if [[ "${PAYER_SECRET_KEY}" != "" ]]; then
  echo "KUBECTL: creating secret ${NAMESPACE}/payer-secret"
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
  echo "KUBECTL: secret ${NAMESPACE}/payer-secret created"
fi

if [[ "${LANDING_ENABLED}" != "" && "${LANDING_ENABLED}" == "true" ]]; then
  echo "HELM: Installing Switchboard Landing page under namespace ${LANDING_NAMESPACE}"
  helm upgrade -i "sb-landing-page" \
    -n "${LANDING_NAMESPACE}" --create-namespace \
    -f "${helm_default_values_file}" \
    -f "${tmp_helm_file}" \
    --set components.landing.namespace="${LANDING_NAMESPACE}" \
    --set components.landing.image="${LANDING_IMAGE}" \
    --set components.landing.image_tag="${LANDING_IMAGE_TAG}" \
    "${helm_landing_page_chart_dir}" >/dev/null
  echo "HELM: Switchboard Landing page installed under namespace ${LANDING_NAMESPACE}"
fi

rm "${tmp_helm_file}"

set -u
