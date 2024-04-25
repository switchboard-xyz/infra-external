#!/usr/bin/env bash
set -u -e

# import vars
source ./00-vars.cfg

helm_values_files="../../chains/solana/${NETWORK}-pull.yaml"
helm_chart_dir="../../charts/pull-service/"
tmp_helm_file="/tmp/helm_values.yaml"
cp "${helm_values_files}" "${tmp_helm_file}"

sed 's?__INFISICAL_SECRETS_PATH__?'"${INFISICAL_SECRETS_PATH}"'?g' "${tmp_helm_file}"
sed 's?__INFISICAL_SLUG__?'"${INFISICAL_SLUG}"'?g' "${tmp_helm_file}"
sed 's?__CLUSTER_DOMAIN__?'"${CLUSTER_DOMAIN}"'?g' "${tmp_helm_file}"
sed 's?__GUARDIAN_QUEUE__?'"${GUARDIAN_QUEUE}"'?g' "${tmp_helm_file}"
sed 's?__GUARDIAN_ORACLE1__?'"${GUARDIAN_ORACLE1}"'?g' "${tmp_helm_file}"
sed 's?__ORACLE1__?'"${ORACLE1}"'?g' "${tmp_helm_file}"
sed 's?__QUEUE__?'"${QUEUE}"'?g' "${tmp_helm_file}"

# install the helm chart
helm upgrade -i pull-oracle-${NETWORK} \
	-n "${NAMESPACE}" --create-namespace \
	-f "${tmp_helm_file}" \
	"${helm_chart_dir}"

rm "${tmp_helm_file}"
