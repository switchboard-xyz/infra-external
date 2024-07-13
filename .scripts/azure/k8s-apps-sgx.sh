#!/usr/bin/env bash
set -u -e

# import vars
source ../../../cfg/00-common-vars.cfg

if [[ "${EMAIL}" == "YOUR@EMAIL.IS.NEEDED.HERE" || "${EMAIL}" == "" ]]; then
  echo "INVALID EMAIL - Please fill out correctly all details in \$REPO/cfg/00-common-vars.cfg"
  exit 1
fi

if [[ "${IP4}" == "0.0.0.0" || "${IP4}" == "" ]]; then
  echo "INVALID IPv4 - Please fill out correctly all details in \$REPO/cfg/00-common-vars.cfg"
  exit 1
fi

if [[ "$(type -p helm)" == "" ]]; then
  curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg >/dev/null
  sudo apt-get install apt-transport-https --yes
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
  sudo apt-get update
  sudo apt-get install -y helm
fi

helm repo add intel https://intel.github.io/helm-charts/
helm repo add nfd https://kubernetes-sigs.github.io/node-feature-discovery/charts

helm repo update

helm upgrade --install \
  --create-namespace --namespace node-feature-discovery \
  --version 0.15.1 nfd \
  nfd/node-feature-discovery

helm upgrade --install \
  --create-namespace --namespace sgx \
  --version v0.29.0 device-plugin-operator \
  intel/intel-device-plugins-operator

sleep 45s

helm upgrade --install \
  --create-namespace --namespace sgx \
  --version v0.29.0 sgx-device-plugin \
  --set nodeFeatureRule=true \
  intel/intel-device-plugins-sgx
