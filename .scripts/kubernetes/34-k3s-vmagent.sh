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

helm repo add vm https://victoriametrics.github.io/helm-charts/
helm repo update

kubectl create configmap \
	-n vmagent-${cluster} \
	vmagent-env \
	--from-file=../../../cfg/00-${cluster}-vars.cfg

helm upgrade -i vmagent-${cluster} \
	-n vmagent-${cluster} --create-namespace \
	-f ../../../.scripts/kubernetes/99-vmagent.yaml \
	vm/victoria-metrics-agent