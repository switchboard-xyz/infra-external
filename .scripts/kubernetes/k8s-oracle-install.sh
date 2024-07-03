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
  kubectl \
    -n "${NAMESPACE}" \
    delete secret payer-secret >/dev/null 2>&1

  # re-create secret
  kubectl \
    -n "${NAMESPACE}" \
    create secret generic \
    --from-file="${PAYER_SECRET_KEY}=../../../data/${cluster}_payer.json" \
    payer-secret
fi

helm upgrade -i "sb-oracle-${NETWORK}" \
  -n "${NAMESPACE}" --create-namespace \
  -f "${helm_default_values_file}" \
  -f "${tmp_helm_file}" \
  "${helm_chart_dir}"

rm "${tmp_helm_file}"
