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

export ORACLE_DOCKER_IMAGE=""
export GUARDIAN_DOCKER_IMAGE=""
export GATEWAY_DOCKER_IMAGE=""

if [[ "${cluster}" == "devnet" ]]; then
  ORACLE_DOCKER_IMAGE="docker.io/switchboardlabs/oracle:devnet"
  GUARDIAN_DOCKER_IMAGE="docker.io/switchboardlabs/guardian:devnet"
  GATEWAY_DOCKER_IMAGE="docker.io/switchboardlabs/gateway:devnet"
else
  ORACLE_DOCKER_IMAGE="docker.io/switchboardlabs/oracle:stable"
  GUARDIAN_DOCKER_IMAGE="docker.io/switchboardlabs/guardian:stable"
  GATEWAY_DOCKER_IMAGE="docker.io/switchboardlabs/gateway:stable"
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
  echo "KUBECTL: creating Namespace ${NAMESPACE}"
  kubectl create namespace "${NAMESPACE}"
  echo "KUBECTL: Namespace ${NAMESPACE} created"
fi

helm_dir="../../../.scripts/helm/"
helm_chart_dir="${helm_dir}/charts/on-demand/"
helm_default_values_file="${helm_chart_dir}/values.yaml"
helm_values_file="${helm_dir}/cfg/${cluster}-solana-values.yaml"
tmp_helm_file="/tmp/helm_values.yaml"

cp "${helm_values_file}" "${tmp_helm_file}"

source ../../../.scripts/var/_load_vars.sh
set +u
load_vars "${tmp_helm_file}" >/dev/null 2>&1

echo "HELM: Installing Switchboard Oracle under namespace ${NAMESPACE}"
helm upgrade -i "sb-oracle-${NETWORK}" \
  -n "${NAMESPACE}" --create-namespace \
  -f "${helm_default_values_file}" \
  -f "${tmp_helm_file}" \
  --set components.oracle.image="${ORACLE_DOCKER_IMAGE}" \
  --set components.guardian.image="${GUARDIAN_DOCKER_IMAGE}" \
  --set components.gateway.image="${GATEWAY_DOCKER_IMAGE}" \
  --set components.guardian.enabled="${GUARDIAN_ENABLED}" \
  "${helm_chart_dir}" >/dev/null
echo "HELM: Switchboard Oracle installed under namespace ${NAMESPACE}"

rm "${tmp_helm_file}"

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
set -u
