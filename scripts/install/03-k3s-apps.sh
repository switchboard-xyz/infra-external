helm repo add jetstack https://charts.jetstack.io

# if needed, update the version below to the latest one at the chart page:
# https://artifacthub.io/packages/helm/cert-manager/cert-manager
helm upgrade -i cert-manager \
	--version v1.14.4 \
	--create-namespace \
	--namespace cert-manager \
	--set installCRDs=true \
	--set global.leaderElection.namespace=cert-manager \
	jetstack/cert-manager

# import vars
source ./00-vars.cfg

if [[ "${EMAIL}" == "YOUR@EMAIL.IS.NEEDED.HERE" || "${EMAIL}"} == "" ]]; then
	echo "INVALID EMAIL - Please fill out correctly all details in ./00-vars.cfg"
	exit 1
fi

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

sleep 10s

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

helm upgrade -i ingress-nginx ingress-nginx/ingress-nginx \
	--namespace ingress-nginx \
	--create-namespace \
	--timeout 600s

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

if [[ "${IP4}" == "0.0.0.0" || "${IP4}" == "" ]]; then
	echo "INVALID IPv4 - Please fill out correctly all details in ./00-vars.cfg"
	exit 1
fi

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

sleep 10s

helm repo add intel https://intel.github.io/helm-charts/
helm repo add nfd https://kubernetes-sigs.github.io/node-feature-discovery/charts

helm repo update

helm upgrade --install \
	--create-namespace --namespace node-feature-discovery \
	--version 0.15.1 nfd \
	nfd/node-feature-discovery

helm upgrade --install \
	--create-namespace --namespace sgx \
	--version v0.29.0 device-plugin-operator \
	intel/intel-device-plugins-operator

helm upgrade --install \
	--create-namespace --namespace sgx \
	--version v0.29.0 sgx-device-plugin \
	--set nodeFeatureRule=true \
	intel/intel-device-plugins-sgx

sleep 10s

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

sleep 10s

helm repo add vm https://victoriametrics.github.io/helm-charts/

helm upgrade -i vmagent \
	-n vmagent --create-namespace \
	-f ./99-vmagent.yaml \
	vm/victoria-metrics-agent

sleep 10s
