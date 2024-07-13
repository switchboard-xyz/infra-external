#!/usr/bin/env bash
set -u -e

platform="$(echo ${1:-bare-metal} | tr '[:upper:]' '[:lower:]')"
if [[ "${platform}" != "bare-metal" &&
  "${platform}" != "azure" ]]; then
  echo "Only valid 'platform' values are 'bare-metal' (default) and 'azure'."
  echo "syntax: $0 [<platform>]"
  exit 1
fi

ingressClass="nginx"
if [[ "${platform}" == "azure" ]]; then
  ingressClass="azure-application-gateway"
fi

# import vars
source ../../../cfg/00-common-vars.cfg

if [[ "${EMAIL}" == "YOUR@EMAIL.IS.NEEDED.HERE" || "${EMAIL}" == "" ]]; then
  echo "INVALID EMAIL - Please fill out correctly all details in \$REPO/cfg/00-common-vars.cfg"
  exit 1
fi

if [[ "$(type -p helm)" == "" ]]; then
  echo "HELM: binary not found.. please install it and add it to path"
  exit 1
fi

echo "HELM: adding jetstack repo"
helm repo add jetstack https://charts.jetstack.io >/dev/null
helm repo update >/dev/null
echo "HELM: jetstack repo added"

# if needed, update the version below to the latest one at the chart page:
# https://artifacthub.io/packages/helm/cert-manager/cert-manager
echo "HELM: installing cert-manager in your cluster"
helm upgrade -i cert-manager \
  --version v1.14.4 \
  --create-namespace \
  --namespace cert-manager \
  --set installCRDs=true \
  --set global.leaderElection.namespace=cert-manager \
  jetstack/cert-manager >/dev/null
echo "HELM: cert-manager installed"

echo "KUBECTL: creating CertIssuer configuration via kubectl in your cluster"
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
	            ingressClassName: ${ingressClass}
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
	            ingressClassName: ${ingressClass}
EOF
  kubectl apply -f - >/dev/null
echo "KUBECTL: CertIssuer configuration created"
