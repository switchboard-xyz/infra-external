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

cfg_dir="../../../cfg"
cfg_common_file="${cfg_dir}/00-common-vars.cfg"
cfg_cluster_file="${cfg_dir}/00-${cluster}-vars.cfg"

# import vars
source "${cfg_common_file}"
source "${cfg_cluster_file}"

echo "===="
echo " "

if [[ "$(kubectl get ns | grep -e '^'${NAMESPACE}'\W')" == "" ]]; then
  kubectl create namespace "${NAMESPACE}"
fi

helm_dir="../../../.scripts/helm/"
helm_chart_dir="${helm_dir}/charts/pull-service/"
helm_default_values_file="${helm_chart_dir}/values.yaml"
helm_values_file="${helm_dir}/cfg/${cluster}-solana-values.yaml"
tmp_helm_file="/tmp/helm_values.yaml"

cp "${helm_values_file}" "${tmp_helm_file}"

source ../../../.scripts/var/_load_vars.sh
set +u
load_vars "${tmp_helm_file}" >/dev/null 2>&1
set -u

if [[ "${PAYER_SECRET_KEY}" != "" ]]; then
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
    payer-secret
fi

export ORACLE_DOCKER_IMAGE=""
export GUARDIAN_DOCKER_IMAGE=""
export GATEWAY_DOCKER_IMAGE=""

if [[ "${cluster}" == "devnet" ]]; then
  ORACLE_DOCKER_IMAGE="docker.io/switchboardlabs/pull-oracle:devnet"
  GUARDIAN_DOCKER_IMAGE="docker.io/switchboardlabs/pull-oracle:devnet"
  GATEWAY_DOCKER_IMAGE="docker.io/switchboardlabs/pull-oracle:devnet"
else
  ORACLE_DOCKER_IMAGE="docker.io/switchboardlabs/pull-oracle:stable"
  GUARDIAN_DOCKER_IMAGE="docker.io/switchboardlabs/pull-oracle:stable"
  GATEWAY_DOCKER_IMAGE="docker.io/switchboardlabs/pull-oracle:stable"
fi

helm upgrade -i "sb-oracle-${NETWORK}" \
  -n "${NAMESPACE}" --create-namespace \
  -f "${helm_default_values_file}" \
  -f "${tmp_helm_file}" \
  --set components.oracle.image="${ORACLE_DOCKER_IMAGE}" \
  --set components.guardian.image="${GUARDIAN_DOCKER_IMAGE}" \
  --set components.gateway.image="${GATEWAY_DOCKER_IMAGE}" \
  "${helm_chart_dir}"

rm "${tmp_helm_file}"
