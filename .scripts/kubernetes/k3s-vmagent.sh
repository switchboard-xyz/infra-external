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

helm repo add vm https://victoriametrics.github.io/helm-charts/
helm repo update

VMAGENT_NS="vmagent-${cluster}"
if [[ "$(kubectl get ns | grep -e '^'${VMAGENT_NS}'\W')" == "" ]]; then
  kubectl create namespace "${VMAGENT_NS}"
fi

tmp_helm_file="/tmp/helm_values.yaml"

cat \
  "${cfg_common_file}" \
  "${cfg_cluster_file}" \
  >"${tmp_helm_file}"

source ../../../.scripts/var/_load_vars.sh
set +u
load_vars "${tmp_helm_file}" >/dev/null 2>&1
set -u

set +e
kubectl delete configmap -n "${VMAGENT_NS}" vmagent-env >/dev/null 2>&1
set -e

kubectl create configmap \
  -n "${VMAGENT_NS}" \
  --from-env-file="${tmp_helm_file}" \
  vmagent-env

rm "${tmp_helm_file}"

helm upgrade -i "vmagent-${cluster}" \
  -n "${VMAGENT_NS}" \
  -f "../../../.scripts/kubernetes/vmagent.yaml" \
  vm/victoria-metrics-agent
