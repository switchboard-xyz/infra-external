#!/usr/bin/env bash
set -u -e

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

cfg_dir="../../../cfg"
cfg_common_file="${cfg_dir}/00-common-vars.cfg"
cfg_cluster_file="${cfg_dir}/00-${cluster}-vars.cfg"

# import vars
source "${cfg_common_file}"
source "${cfg_cluster_file}"

echo -n "Please enter your Infisical Access Token (e.g. st.ABC.XYZ): "
read -s INFISICAL_ACCESS_TOKEN
echo "*****"

helm repo add infisical-helm-charts \
  'https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/'

helm upgrade -i secrets-operator \
  -n infisical --create-namespace \
  infisical-helm-charts/secrets-operator

INFISICAL_TOKEN_NAME="infisical-token-${cluster}"

cat <<-EOF |
	apiVersion: secrets.infisical.com/v1alpha1
	kind: InfisicalSecret
	metadata:
	  name: payer-secret-${cluster}
	  namespace: ${INFISICAL_TOKEN_NAMESPACE}
	spec:
	  hostAPI: https://app.infisical.com/api
	  resyncInterval: 60 # seconds
	  authentication:
	    serviceToken:
        # token used to access Infisical API ... created a few lines below
	      serviceTokenSecretReference:
	        secretName: ${INFISICAL_TOKEN_NAME}
	        secretNamespace: ${INFISICAL_TOKEN_NAMESPACE}
        # slug and path for the data inside Infisical
	      secretsScope:
	        envSlug: ${INFISICAL_SECRET_SLUG}
	        secretsPath: ${INFISICAL_SECRET_PATH}
	  managedSecretReference:
      # name and namespace of secret that will be created inside Kubernetes
      # to store the value retrived from Infisical
	    secretName: payer-secret
	    secretNamespace: ${NAMESPACE}
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
	  name: ${INFISICAL_TOKEN_NAME}
	  namespace: ${INFISICAL_TOKEN_NAMESPACE}
	stringData:
	  infisicalToken: ${INFISICAL_ACCESS_TOKEN}
EOF
  kubectl apply -f -

# Scrub the token from the environment
INFISICAL_ACCESS_TOKEN="$(head -c 1024 /dev/urandom | xxd -p)"
unset INFISICAL_ACCESS_TOKEN
