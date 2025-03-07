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

echo "HELM: adding Vector Logs repo"
helm repo add vector https://helm.vector.dev >/dev/null
helm repo update >/dev/null
echo "HELM: Vector Logs repo added"

if [[ "$(kubectl get ns | grep -e '^'${NAMESPACE}'\W')" == "" ]]; then
  echo "KUBECTL: creating namespace ${NAMESPACE}"
  kubectl create namespace "${NAMESPACE}" >/dev/null
  echo "KUBECTL: namespace ${NAMESPACE} created"
fi

set +u
echo "HELM: installing Vector Logs Agent in your cluster"
helm upgrade -i "sb-logs-${cluster}" \
  -n "${NAMESPACE}" \
  --version 0.41.0 \
  --set "rbac.namespaced=true" \
  -f "../../../.scripts/kubernetes/vmlogs.yaml" \
  vector/vector >/dev/null
echo "HELM: Vector Logs Agent installed"
set -u

