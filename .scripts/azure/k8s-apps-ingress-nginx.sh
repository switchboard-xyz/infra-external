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

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade -i ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --timeout 600s

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

if [[ "${IP6}" == "0000::0000" || "${IP6}" == "" ]]; then
  helm upgrade -i ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    --create-namespace \
    --timeout 600s \
    --set controller.kind=DaemonSet \
    --set controller.hostNetwork=true \
    --set controller.hostPort.enabled=true \
    --set controller.service.externalIPs[0]=${IP4}
else
  helm upgrade -i ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    --create-namespace \
    --timeout 600s \
    --set controller.kind=DaemonSet \
    --set controller.hostNetwork=true \
    --set controller.hostPort.enabled=true \
    --set controller.service.externalIPs[0]=${IP4} \
    --set controller.service.externalIPs[1]="${IP6}"
fi
