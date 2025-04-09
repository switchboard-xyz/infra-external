#!/usr/bin/env bash
set -u -e

cluster="${1:-devnet}"

set +u
if [[ -z "${1}" ]]; then
  printf "No cluster specified, using default: 'devnet'\n"
fi
set -u

if [[ "${cluster}" != "devnet" &&
  "${cluster}" != "mainnet" ]]; then
  printf "Only valid cluster values are 'devnet' and 'mainnet'.\n"
  exit 1
fi

cfg_dir="../../../cfg"
cfg_common_file="${cfg_dir}/00-common-vars.cfg"
cfg_cluster_file="${cfg_dir}/00-${cluster}-vars.cfg"

# import vars
source "${cfg_common_file}"
source "${cfg_cluster_file}"

TMP_FILE="./testcert.yml"

printf "\n"
printf "KUBECTL: deleting tmp file and resources created in the previous step.\n"
printf "\n"

kubectl delete -n "${NAMESPACE}" -f "${TMP_FILE}" >/dev/null &&
  rm -f "${TMP_FILE}"

printf "\n"
