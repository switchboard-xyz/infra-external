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

TMP_FILE="./testcert.yml"

echo " "
echo "======"
echo "This step will delete the tmp file and resources created in the previous step."
echo "======"
echo " "

kubectl delete -n "${NAMESPACE}" -f "${TMP_FILE}" && rm -f "${TMP_FILE}"

echo " "
echo "======"
echo "This step is complete, please proceed with the next step."
echo "======"
