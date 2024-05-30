#!/usr/bin/env bash
set -u -e

source ../../cfg/00-common-vars.cfg
source ../../cfg/00-devnet-vars.cfg

helm_values_files="../../.scripts/helm/cfg/devnet-solana-values.yaml"
helm_chart_dir="../../.scripts/helm/charts/pull-service/"
tmp_helm_file="/tmp/helm_values.yaml"
cp "${helm_values_files}" "${tmp_helm_file}"

source ../../.scripts/var/_load_vars.sh
load_vars "${tmp_helm_file}"

# install the helm chart
helm upgrade -i pull-oracle-${NETWORK} \
	-n "${NAMESPACE}" --create-namespace \
	-f "${tmp_helm_file}" \
	"${helm_chart_dir}"

rm "${tmp_helm_file}"
