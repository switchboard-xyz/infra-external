#!/bin/bash

echo "initializing oracle node. Make sure you have set up your ssh key and configured your oracle values yaml"

# Prompt for the IP address
echo "Please enter the IP address:"
read ip_address

ssh "root"@"$ip_address" 

echo "deb https://download.01.org/intel-sgx/sgx_repo/ubuntu $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/intel-sgx.list >/dev/null
curl -sSL "https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key" | sudo -E apt-key add -
sudo apt-get update
sudo apt-get install -y \
    sgx-aesm-service \
    libsgx-aesm-launch-plugin \
    libsgx-aesm-quote-ex-plugin \
    libsgx-aesm-ecdsa-plugin \
    libsgx-aesm-epid-plugin \
    libsgx-dcap-quote-verify \
    syslinux

exit

if ! command -v k3sup &> /dev/null
then
    curl -sLS https://get.k3sup.dev | sh
fi

k3sup install --ip $ip_address --user root --context k3s-oracle --no-extras
echo "k3s installed"
kubectl config use-context k3s-oracle

echo "updating helm charts"
helm repo add intel https://intel.github.io/helm-charts/
helm repo add infisical-helm-charts 'https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/'
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
helm repo update

echo "installing helm charts"

helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.12.3 \
  --set installCRDs=true \
  --set global.leaderElection.namespace=cert-manager

echo "deploy your clusterissuer manifest before proceeding (press enter to continue)"
read tmp

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=NodePort \
  --timeout 600s \
  --debug \
  -f nginx-values.yaml


helm install secrets-operator infisical-helm-charts/secrets-operator
echo "deploy your infisical service-token secret before proceeding (press enter to continue)"
read tmp

 
helm upgrade --install                     \
  --create-namespace --namespace sgx       \
  --version v0.29.0 device-plugin-operator \
  intel/intel-device-plugins-operator
helm upgrade --install                     \
  --create-namespace --namespace sgx       \
  --version v0.29.0 sgx-device-plugin      \
  intel/intel-device-plugins-sgx

export INGRESS_IP="$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o json | jq '.status.loadBalancer.ingress[0].ip')"
echo "input the url you've registered with your DNS provider for this cluster (note: your machine's IP address is $INGRESS_IP)"
read SB_DNS
bash scripts/ingress-init.sh

echo "input the location of your oracle values yaml file"
read ORACLE_YAML

helm upgrade -i pull-oracle-devnet ./charts/pull-service/ -f $ORACLE_YAML
