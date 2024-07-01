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

kubectl delete -f testcert.yml ${NAMESPACE}

rm -f ./testcert.yml
