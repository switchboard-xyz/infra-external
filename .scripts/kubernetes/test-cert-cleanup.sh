#!/usr/bin/env bash
set -u -e

# import vars
source ../../../cfg/00-common-vars.cfg

TMP_FILE="./testcert.yml"

printf "\n"
printf "KUBECTL: deleting test resources created in the previous step.\n"
printf "\n"

kubectl delete -f "${TMP_FILE}" >/dev/null &&
  rm -f "${TMP_FILE}"

printf "\n"
