#!/usr/bin/env bash
set -u -e

SAIL_IMAGE="${1:-switchboardlabs/reporteer:latest}"

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

helm_dir="${repo_dir}/.scripts/helm/"
helm_chart_dir="${helm_dir}/charts/on-demand/"
helm_default_values_file="${helm_chart_dir}/values.yaml"
helm_values_file="${helm_dir}/cfg/${cluster}-solana-values.yaml"
tmp_helm_file="/tmp/helm_values.yaml"

cp "${helm_values_file}" "${tmp_helm_file}"

source "${repo_dir}"/.scripts/var/_load_vars.sh
set +u
load_vars "${tmp_helm_file}" >/dev/null 2>&1

echo "HELM: Installing SAIL under namespace ${NAMESPACE}"
helm upgrade -i "sb-oracle-${NETWORK}" \
  -n "${NAMESPACE}" --create-namespace \
  -f "${helm_default_values_file}" \
  -f "${tmp_helm_file}" \
  --set components.sail_image="${SAIL_IMAGE}" \
  "${helm_chart_dir}" >/dev/null
echo "HELM: Installed SAIL under namespace ${NAMESPACE}"

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
