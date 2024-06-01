#!/usr/bin/env bash
set -u -e

# import vars
source ../../cfg/00-common-vars.cfg

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

source "../../cfg/00-${cluster}-vars.cfg"

helm_values_files="../../.scripts/helm/cfg/${cluster}-solana-values.yaml"
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
