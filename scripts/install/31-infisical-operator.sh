#!/usr/bin/env bash
set -u -e

# import vars
source ./00-vars.cfg
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
	        secretName: service-token
	        secretNamespace: infisical
	      secretsScope:
	        envSlug: ${INFISICAL_SLUG}
	        secretsPath: ${INFISICAL_SECRETS_PATH}
	  managedSecretReference:
	    secretName: keys   # <-- the name of kubernetes secret that will be created
	    secretNamespace: oracle # <-- where the kubernetes secret should be created
EOF
	kubectl apply -f -

if [[ "${INFISICAL_ACCESS_TOKEN}" == "st.ABC.XYZ" || "${INFISICAL_ACCESS_TOKEN}" == "" ]]; then
	echo "INVALID INFISICAL ACCESS TOKEN - Please fill out correctly all details in ./00-vars.cfg"
	exit 1
fi

cat <<-EOF |
	apiVersion: v1
	kind: Secret
	type: Opaque
	metadata:
	  name: service-token
	  namespace: infisical
	stringData:
	  infisicalToken: ${INFISICAL_ACCESS_TOKEN}
EOF
	kubectl apply -f -

