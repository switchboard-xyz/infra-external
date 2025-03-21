#!/usr/bin/env bash
set -u -e

# Check if two arguments are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 alloy-username alloy-password"
    exit 1
fi

alloy_user="$1"
alloy_password="$2"

cfg_dir="../../../cfg"
cfg_common_file="${cfg_dir}/00-common-vars.cfg"
cfg_cluster_file="${cfg_dir}/00-${cluster}-vars.cfg"

# import vars
source "${cfg_common_file}"
source "${cfg_cluster_file}"

# get helm chart dir
repo_dir="$(readlink -f ../../..)"
helm_dir="${repo_dir}/.scripts/helm/"
helm_chart_dir="${helm_dir}/charts/sb-monitoring/"
helm_values_file="${helm_chart_dir}/values.yaml"

echo "HELM: adding Grafana repo"
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo update >/dev/null
echo "HELM: Grafana repo added"

helm_installation=sb-log-forwarding
helm_installation_namespace=sb-log-forwarding

set +u
echo "HELM: installing ${helm_installation}"
helm upgrade -i "${helm_installation}" \
  -n "${helm_installation_namespace}" --create-namespace \
  -f "${helm_values_file}" \
  --set alloy.basicAuth.username="${alloy_user}" \
  --set alloy.basicAuth.password="${alloy_password}" \
  --set alloy.operator="${CLUSTER_DOMAIN}" \
  --set alloy.oracleIP.="${IPv4}" \
  "${helm_chart_dir}" >/dev/null


echo "HELM: $helm_installation installed"
set -u