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

echo "HELM: adding nginx-stable repo"
helm repo add nginx-stable https://helm.nginx.com/stable >/dev/null
helm repo update >/dev/null
echo "HELM: nginx-stable repo added"

echo "HELM: checking for old ingress-nginx release"
if helm list --namespace ingress-nginx --filter '^ingress-nginx$' --short 2>/dev/null | grep -q 'ingress-nginx'; then
  echo "HELM: uninstalling old ingress-nginx release"
  helm uninstall ingress-nginx --namespace ingress-nginx --wait --timeout 600s >/dev/null
  echo "HELM: old ingress-nginx uninstalled"
else
  echo "HELM: no existing ingress-nginx release found, skipping uninstall"
fi

echo "KUBECTL: removing old ingress-nginx cluster-scoped resources"
# ValidatingWebhookConfiguration must be removed explicitly — if it lingers after the
# controller pod is gone, all Ingress admission calls will hang indefinitely.
kubectl delete validatingwebhookconfiguration ingress-nginx-admission --ignore-not-found >/dev/null
# IngressClass/nginx must be removed so the F5 controller can register a clean one.
kubectl delete ingressclass nginx --ignore-not-found >/dev/null
echo "KUBECTL: old ingress-nginx cluster-scoped resources removed"

echo "KUBECTL: removing old ingress-nginx namespace"
kubectl delete namespace ingress-nginx --ignore-not-found >/dev/null
echo "KUBECTL: old ingress-nginx namespace removed"

echo "HELM: installing nginx-ingress in your cluster"
if [[ "${platform}" == "azure" ]]; then
  if [[ "${IPv6}" == "0000::0000" || "${IPv6}" == "" ]]; then
    helm upgrade -i nginx-ingress nginx-stable/nginx-ingress \
      --namespace nginx-ingress \
      --create-namespace \
      --timeout 600s \
      --set controller.kind=daemonset \
      --set controller.service.type=LoadBalancer \
      --set controller.service.externalTrafficPolicy=Local \
      --set controller.nodeSelector."kubernetes\.io/os"=linux \
      --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-ipv4"="${IPv4}" \
      >/dev/null
  else
    helm upgrade -i nginx-ingress nginx-stable/nginx-ingress \
      --namespace nginx-ingress \
      --create-namespace \
      --timeout 600s \
      --set controller.kind=daemonset \
      --set controller.service.type=LoadBalancer \
      --set controller.service.externalTrafficPolicy=Local \
      --set controller.nodeSelector."kubernetes\.io/os"=linux \
      --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-ipv4"="${IPv4}" \
      >/dev/null
  fi
else
  if [[ "${IPv6}" == "0000::0000" || "${IPv6}" == "" ]]; then
    helm upgrade -i nginx-ingress nginx-stable/nginx-ingress \
      --namespace nginx-ingress \
      --create-namespace \
      --timeout 600s \
      --set controller.kind=daemonset \
      --set controller.hostNetwork=true \
      --set controller.service.externalTrafficPolicy=Local \
      --set controller.service.externalIPs[0]="${IPv4}" \
      >/dev/null
  else
    helm upgrade -i nginx-ingress nginx-stable/nginx-ingress \
      --namespace nginx-ingress \
      --create-namespace \
      --timeout 600s \
      --set controller.kind=daemonset \
      --set controller.hostNetwork=true \
      --set controller.service.externalTrafficPolicy=Local \
      --set controller.service.externalIPs[0]="${IPv4}" \
      --set controller.service.externalIPs[1]="${IPv6}" \
      >/dev/null
  fi
fi
echo "HELM: nginx-ingress installed"
