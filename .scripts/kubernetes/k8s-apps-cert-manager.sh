#!/usr/bin/env bash
set -u -e

ingressClass="nginx"

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
  --version v1.15.1 \
  --create-namespace \
  --namespace cert-manager \
  --set crds.enabled=true \
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
	            serviceType: ClusterIP
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
	            serviceType: ClusterIP
EOF
  kubectl apply -f - >/dev/null
echo "KUBECTL: CertIssuer configuration created"
