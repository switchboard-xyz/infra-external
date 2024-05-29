#!/usr/bin/env bash
set -u -e

helm_values_files="../../chains/solana/values.yaml"
helm_chart_dir="../../charts/pull-service/"
tmp_helm_file="/tmp/helm_values.yaml"
cp "${helm_values_files}" "${tmp_helm_file}"

source ../../../cfg/00-vars.cfg
source ../../.scripts/var/_load_vars.sh
load_vars "${tmp_helm_file}"

# install the helm chart
helm upgrade -i pull-oracle-${NETWORK} \
	-n "${NAMESPACE}" --create-namespace \
	-f "${tmp_helm_file}" \
	"${helm_chart_dir}"

rm "${tmp_helm_file}"
