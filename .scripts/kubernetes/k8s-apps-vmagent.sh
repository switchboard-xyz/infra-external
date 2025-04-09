#!/usr/bin/env bash
set -u -e

cluster="${1:-devnet}"

if [[ -z "${1}" ]]; then
  printf "No cluster specified, using default: 'devnet'\n"
fi

if [[ "${cluster}" != "devnet" &&
  "${cluster}" != "mainnet" ]]; then
  echo "Only valid cluster values are 'devnet' and 'mainnet'."
  exit 1
fi

cfg_dir="../../../cfg"
cfg_common_file="${cfg_dir}/00-common-vars.cfg"
cfg_cluster_file="${cfg_dir}/00-${cluster}-vars.cfg"

# import vars
source "${cfg_common_file}"
source "${cfg_cluster_file}"

printf "HELM: adding VictoriaMetrics repo\n"
helm repo add vm https://victoriametrics.github.io/helm-charts/ >/dev/null
helm repo update >/dev/null
printf "HELM: VictoriaMetrics repo added\n"

if [[ "$(kubectl get ns | grep -e '^'${NAMESPACE}'\W')" == "" ]]; then
  printf "KUBECTL: creating namespace ${NAMESPACE}\n"
  kubectl create namespace "${NAMESPACE}" >/dev/null
  printf "KUBECTL: namespace ${NAMESPACE} created\n"
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

printf "KUBECTL: creating ConfigMap ${NAMESPACE}/vmagent-env (remove and recreate if exists)\n"
set +e
kubectl delete configmap -n "${NAMESPACE}" vmagent-env >/dev/null 2>&1
set -e

kubectl create configmap \
  -n "${NAMESPACE}" \
  --from-env-file="${tmp_helm_file}" \
  vmagent-env >/dev/null
printf "KUBECTL: creation completed\n"

rm "${tmp_helm_file}"

printf "HELM: installing VictoriaMetrics Agent in your cluster\n"
helm upgrade -i "vmagent-${cluster}" \
  -n "${NAMESPACE}" \
  --set "rbac.namespaced=true" \
  -f "../../../.scripts/kubernetes/vmagent.yaml" \
  vm/victoria-metrics-agent >/dev/null
printf "HELM: VictoriaMetrics Agent installed\n"

repo_dir="$(readlink -f ../../..)"
helm_dir="${repo_dir}/.scripts/helm/"
helm_chart_dir="${helm_dir}/charts/sb-monitoring/"
helm_values_file="${helm_chart_dir}/values.yaml"

set +u
printf "HELM: Adding prometheus-community repo\n"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo update >/dev/null
printf "HELM: prometheus-community repo added\n"

printf "HELM: Installing switchboard-monitoring under namespace sb-monitoring\n"
helm dependency build ${helm_chart_dir} >/dev/null
helm upgrade -i "sb-monitoring" \
  -n "sb-monitoring" --create-namespace \
  -f "${helm_values_file}" \
  --set victoria-metrics-agent.config.global.external_labels.operator="${CLUSTER_DOMAIN}" \
  "${helm_chart_dir}" >/dev/null
printf "HELM: Installed sb-monitoring under namespace sb-monitoring\n"
set -u

