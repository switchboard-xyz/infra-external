#!/usr/bin/env bash
set -u -e

# import vars
source ../../../cfg/00-common-vars.cfg

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

source "../../../cfg/00-${cluster}-vars.cfg"

helm repo add vm https://victoriametrics.github.io/helm-charts/
helm repo update

VMAGENT_NS="vmagent-${cluster}"
if [[ "$(kubectl get ns | grep -e '^'${VMAGENT_NS}'\W')" == "" ]]; then
  kubectl create namespace "${VMAGENT_NS}"
fi

kubectl delete configmap -n "${VMAGENT_NS}" vmagent-env >/dev/null 2>&1

kubectl create configmap \
  -n "${VMAGENT_NS}" \
  --from-file="../../../cfg/00-common-vars.cfg" \
  --from-file="../../../cfg/00-${cluster}-vars.cfg" \
  vmagent-env

helm upgrade -i "vmagent-${cluster}" \
  -n "${VMAGENT_NS}" \
  -f "../../../.scripts/kubernetes/vmagent.yaml" \
  vm/victoria-metrics-agent
