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

echo "HELM: adding VictoriaMetrics repo"
helm repo add vm https://victoriametrics.github.io/helm-charts/ >/dev/null
helm repo update >/dev/null
echo "HELM: VictoriaMetrics repo added"

if [[ "$(kubectl get ns | grep -e '^'${NAMESPACE}'\W')" == "" ]]; then
  echo "KUBECTL: creating namespace ${NAMESPACE}"
  kubectl create namespace "${NAMESPACE}" >/dev/null
  echo "KUBECTL: namespace ${NAMESPACE} created"
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

echo "KUBECTL: creating ConfigMap ${NAMESPACE}/vmagent-env (remove and recreate if exists)"
set +e
kubectl delete configmap -n "${NAMESPACE}" vmagent-env >/dev/null 2>&1
set -e

kubectl create configmap \
  -n "${NAMESPACE}" \
  --from-env-file="${tmp_helm_file}" \
  vmagent-env >/dev/null
echo "KUBECTL: creation completed"

rm "${tmp_helm_file}"

echo "HELM: installing VictoriaMetrics Agent in your cluster"
helm upgrade -i "vmagent-${cluster}" \
  -n "${NAMESPACE}" \
  --set "rbac.namespaced=true" \
  -f "../../../.scripts/kubernetes/vmagent.yaml" \
  vm/victoria-metrics-agent >/dev/null
echo "HELM: VictoriaMetrics Agent installed"

repo_dir="$(readlink -f ../../..)"
helm_dir="${repo_dir}/.scripts/helm/"
helm_chart_dir="${helm_dir}/charts/sb-monitoring/"
helm_values_file="${helm_chart_dir}/values.yaml"

set +u

echo "HELM: Installing switchboard-monitoring under namespace sb-monitoring"
helm dependency build ${helm_chart_dir}
helm upgrade -i "sb-monitoring" \
  -n "sb-monitoring" --create-namespace \
  -f "${helm_values_file}" \
  --set victoria-metrics-agent.config.global.external_labels.operator="${CLUSTER_DOMAIN}" \
  "${helm_chart_dir}" >/dev/null
echo "HELM: Installed sb-monitoring under namespace sb-monitoring"
set -u