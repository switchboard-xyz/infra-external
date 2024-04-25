#!/usr/bin/env bash
set -u -e

# import vars
source ./00-vars.cfg

helm_values_files="../../chains/solana/${NETWORK}-pull.yaml"
helm_chart_dir="../../charts/pull-service/"

sed -i 's?__INFISICAL_SECRETS_PATH__?'"${INFISICAL_SECRETS_PATH}"'?g' "${helm_values_files}"
sed -i 's?__INFISICAL_SLUG__?'"${INFISICAL_SLUG}"'?g' "${helm_values_files}"
sed -i 's?__CLUSTER_DOMAIN__?'"${CLUSTER_DOMAIN}"'?g' "${helm_values_files}"
sed -i 's?__GUARDIAN_QUEUE__?'"${GUARDIAN_QUEUE}"'?g' "${helm_values_files}"
sed -i 's?__GUARDIAN_ORACLE1__?'"${GUARDIAN_ORACLE1}"'?g' "${helm_values_files}"
sed -i 's?__ORACLE1__?'"${ORACLE1}"'?g' "${helm_values_files}"
sed -i 's?__QUEUE__?'"${QUEUE}"'?g' "${helm_values_files}"

# install the helm chart
helm upgrade -i pull-oracle-${NETWORK} \
	-n "${NAMESPACE}" --create-namespace \
	-f "${helm_values_files}" \
	"${helm_chart_dir}"
