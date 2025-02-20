#!/usr/bin/env bash
set -u -e

SAIL_IMAGE="${1:-switchboardlabs/reporteer:latest}"
NAMESPACE="sail"

repo_dir="$(readlink -f ../../..)"

cfg_dir="${repo_dir}/cfg"
cfg_common_file="${cfg_dir}/00-common-vars.cfg"

# import vars
source "${cfg_common_file}"

echo "===="
echo " "

if [[ "$(kubectl get ns | grep -e '^'${NAMESPACE}'\W')" == "" ]]; then
  echo "KUBECTL: creating Namespace ${NAMESPACE}"
  kubectl create namespace "${NAMESPACE}"
  echo "KUBECTL: Namespace ${NAMESPACE} created"
fi

helm_dir="${repo_dir}/.scripts/helm/"
helm_chart_dir="${helm_dir}/charts/sail/"
helm_values_file="${helm_chart_dir}/values.yaml"

set +u

echo "HELM: Installing SAIL under namespace ${NAMESPACE}"
helm upgrade -i "sb-sail" \
  -n "${NAMESPACE}" --create-namespace \
  -f "${helm_values_file}" \
  --set sail.image="${SAIL_IMAGE}" \
  --set ingress.enabled="true" \
  --set ingress.hosts[0]="${CLUSTER_DOMAIN}" \
  --set ingress.tls.issuer="letsencrypt-prod-http" \
  "${helm_chart_dir}" >/dev/null
echo "HELM: Installed SAIL under namespace ${NAMESPACE}"
set -u
