#!/usr/bin/env bash
set -u -e

platform="$(echo ${1:-bare-metal} | tr '[:upper:]' '[:lower:]')"
if [[ "${platform}" != "bare-metal" &&
  "${platform}" != "azure" ]]; then
  echo "Only valid 'platform' values are 'bare-metal' (default) and 'azure'."
  echo "syntax: $0 [<platform>]"
  exit 1
fi

# import vars
source ../../../cfg/00-common-vars.cfg

if [[ "${EMAIL}" == "YOUR@EMAIL.IS.NEEDED.HERE" || "${EMAIL}" == "" ]]; then
  echo "INVALID EMAIL - Please fill out correctly all details in \$REPO/cfg/00-common-vars.cfg"
  exit 1
fi

if [[ "${IPv4}" == "0.0.0.0" || "${IPv4}" == "" ]]; then
  echo "INVALID IPv4 - Please fill out correctly all details in \$REPO/cfg/00-common-vars.cfg"
  exit 1
fi

if [[ "$(type -p helm)" == "" ]]; then
  echo "HELM: binary not found.. please install it and add it to path"
  exit 1
fi

echo "HELM: adding ingress-nginx repo"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null
helm repo update >/dev/null
echo "HELM: ingress-nginx repo added"

echo "HELM: installing ingress-nginx in your cluster"
if [[ "${platform}" == "azure" ]]; then
  if [[ "${IPv6}" == "0000::0000" || "${IPv6}" == "" ]]; then
    helm upgrade -i ingress-nginx ingress-nginx/ingress-nginx \
      --namespace ingress-nginx \
      --create-namespace \
      --timeout 600s \
      --set controller.kind=DaemonSet \
      --set controller.service.type=LoadBalancer \
      --set controller.service.externalTrafficPolicy=Local \
      --set controller.nodeSelector."kubernetes\.io/os"=linux \
      --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux \
      --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-ipv4"="${IPv4}" \
      >/dev/null
  else
    helm upgrade -i ingress-nginx ingress-nginx/ingress-nginx \
      --namespace ingress-nginx \
      --create-namespace \
      --timeout 600s \
      --set controller.kind=DaemonSet \
      --set controller.service.type=LoadBalancer \
      --set controller.service.externalTrafficPolicy=Local \
      --set controller.nodeSelector."kubernetes\.io/os"=linux \
      --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux \
      --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-ipv4"="${IPv4}" \
      >/dev/null
  fi
else
  if [[ "${IPv6}" == "0000::0000" || "${IPv6}" == "" ]]; then
    helm upgrade -i ingress-nginx ingress-nginx/ingress-nginx \
      --namespace ingress-nginx \
      --create-namespace \
      --timeout 600s \
      --set controller.kind=DaemonSet \
      --set controller.hostNetwork=true \
      --set controller.hostPort.enabled=true \
      --set controller.service.externalTrafficPolicy=Local \
      --set controller.service.externalIPs[0]="${IPv4}" \
      >/dev/null
  else
    helm upgrade -i ingress-nginx ingress-nginx/ingress-nginx \
      --namespace ingress-nginx \
      --create-namespace \
      --timeout 600s \
      --set controller.kind=DaemonSet \
      --set controller.hostNetwork=true \
      --set controller.hostPort.enabled=true \
      --set controller.service.externalTrafficPolicy=Local \
      --set controller.service.externalIPs[0]="${IPv4}" \
      --set controller.service.externalIPs[1]="${IPv6}" \
      >/dev/null
  fi
fi
echo "HELM: ingress-nginx installed"
