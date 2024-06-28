#!/usr/bin/env bash
set -u -e

# import vars
source ../../cfg/00-common-vars.cfg

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

source "../../cfg/00-${cluster}-vars.cfg"

echo -n "Please enter your Infisical Access Token (e.g. st.ABC.XYZ): "
read -s INFISICAL_ACCESS_TOKEN
echo "*****"

helm repo add infisical-helm-charts \
	'https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/'

helm upgrade -i secrets-operator \
	-n infisical --create-namespace \
	infisical-helm-charts/secrets-operator

cat <<-EOF |
	apiVersion: secrets.infisical.com/v1alpha1
	kind: InfisicalSecret
	metadata:
	  name: solana-key
	  namespace: infisical
	spec:
	  hostAPI: https://app.infisical.com/api
	  resyncInterval: 60 # seconds
	  authentication:
	    serviceToken:
	      serviceTokenSecretReference:
	        secretName: service-token-${cluster}
	        secretNamespace: infisical
	      secretsScope:
	        envSlug: ${INFISICAL_SLUG}
	        secretsPath: ${INFISICAL_SECRETS_PATH}
	  managedSecretReference:
	    secretName: keys   # <-- the name of kubernetes secret that will be created
	    secretNamespace: ${NAMESPACE} # <-- where the kubernetes secret should be created, source by cfg/00-{devnet,mainnet}-vars.cfg
EOF
	kubectl apply -f -

if [[ "${INFISICAL_ACCESS_TOKEN}" == "st.ABC.XYZ" || "${INFISICAL_ACCESS_TOKEN}" == "" ]]; then
	echo "INVALID INFISICAL ACCESS TOKEN - Please fill out correctly all details in \$REPO/cfg./00-{devnet,mainnet}-vars.cfg"
	exit 1
fi

cat <<-EOF |
	apiVersion: v1
	kind: Secret
	type: Opaque
	metadata:
	  name: service-token-${cluster}
	  namespace: infisical
	stringData:
	  infisicalToken: ${INFISICAL_ACCESS_TOKEN}
EOF
	kubectl apply -f -

# Scrub the token from the environment
INFISICAL_ACCESS_TOKEN="$(head -c 1024 /dev/urandom | xxd -p)"
unset INFISICAL_ACCESS_TOKEN
