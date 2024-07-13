#!/usr/bin/env bash
set -u -e

if [[ "$(type -p helm)" == "" ]]; then
  echo "HELM: binary not found.. please install it and add it to path"
  exit 1
fi

echo "HELM: adding SGX & NFD repos"
helm repo add intel https://intel.github.io/helm-charts/ >/dev/null 2>&1
helm repo add nfd https://kubernetes-sigs.github.io/node-feature-discovery/charts >/dev/null 2>&1
helm repo update >/dev/null 2>&1
echo "HELM: SGX & NFD repos added"

echo "HELM: installing NodeFeatureDiscovery"
helm upgrade --install \
  --create-namespace --namespace node-feature-discovery \
  --version 0.15.1 nfd \
  nfd/node-feature-discovery >/dev/null
echo "HELM: NodeFeatureDiscovery installed"

echo "HELM: installing IntelDeviceOperator"
helm upgrade --install \
  --create-namespace --namespace sgx \
  --version v0.29.0 device-plugin-operator \
  intel/intel-device-plugins-operator >/dev/null
echo "HELM: IntelDeviceOperator installed"

export wait_time="45s"
echo "HELM: waiting ${wait_time} for NFD to pick up and tag nodes"
sleep "${wait_time}"

echo "HELM: installing IntelDeviceOperator"
helm upgrade --install \
  --create-namespace --namespace sgx \
  --version v0.29.0 sgx-device-plugin \
  --set nodeFeatureRule=true \
  intel/intel-device-plugins-sgx >/dev/null
echo "HELM: IntelDeviceOperator installed"
