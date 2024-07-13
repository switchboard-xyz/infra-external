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

helm repo add jetstack https://charts.jetstack.io
helm repo update

# if needed, update the version below to the latest one at the chart page:
# https://artifacthub.io/packages/helm/cert-manager/cert-manager
helm upgrade -i cert-manager \
  --version v1.14.4 \
  --create-namespace \
  --namespace cert-manager \
  --set installCRDs=true \
  --set global.leaderElection.namespace=cert-manager \
  jetstack/cert-manager

cat <<-EOF |
	---
	apiVersion: cert-manager.io/v1
	kind: ClusterIssuer
	metadata:
	  name: internal-issuer
	spec:
	  selfSigned: {}
	---
	apiVersion: cert-manager.io/v1
	kind: ClusterIssuer
	metadata:
	  name: letsencrypt-staging-http
	spec:
	  acme:
	    server: https://acme-staging-v02.api.letsencrypt.org/directory
	    email: ${EMAIL}
	    privateKeySecretRef:
	      name: letsencrypt-staging-http
	    solvers:
	      - http01:
	          ingress:
	            ingressClassName: nginx
	---
	apiVersion: cert-manager.io/v1
	kind: ClusterIssuer
	metadata:
	  name: letsencrypt-prod-http
	spec:
	  acme:
	    server: https://acme-v02.api.letsencrypt.org/directory
	    email: ${EMAIL}
	    privateKeySecretRef:
	      name: letsencrypt-prod-http
	    solvers:
	      - http01:
	          ingress:
	            ingressClassName: nginx
EOF
  kubectl apply -f -
