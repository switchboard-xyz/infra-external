#!/usr/bin/env bash
set -u -e

# import vars
source ../../../cfg/00-common-vars.cfg

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

source "../../../cfg/00-${cluster}-vars.cfg"

if [[ "$(kubectl get ns | grep -e '^'${NAMESPACE}'\W')" == "" ]]; then
	kubectl create namespace "${NAMESPACE}"
fi

TMP_FILE="./testcert.yml"

cat >"${TMP_FILE}" <<-EOF
	---
	apiVersion: networking.k8s.io/v1
	kind: Ingress
	metadata:
	  name: nginx
	  annotations:
	    cert-manager.io/cluster-issuer: letsencrypt-staging-http
	spec:
	  ingressClassName: nginx
	  tls:
	  - hosts:
	    - ${CLUSTER_DOMAIN}
	    secretName: letsencrypt-staging-http
	  rules:
	    - host: ${CLUSTER_DOMAIN}
	      http:
	        paths:
	          - path: /
	            pathType: Prefix
	            backend:
	              service:
	                name: nginx
	                port:
	                  number: 80
	---
	apiVersion: v1
	kind: Service
	metadata:
	  name: nginx
	spec:
	  type: ClusterIP
	  ports:
	    - port: 80
	      targetPort: 80
	  selector:
	    app: nginx
	---
	apiVersion: apps/v1
	kind: Deployment
	metadata:
	  name: nginx
	spec:
	  selector:
	    matchLabels:
	      app: nginx
	  template:
	    metadata:
	      labels:
	        app: nginx
	    spec:
	      containers:
	        - image: nginx
	          name: nginx
	          ports:
	            - containerPort: 80
EOF
kubectl apply -f "${TMP_FILE}" -n "${NAMESPACE}"

echo "======"
echo " "
echo "Now give the certificate about 3-5 minutes to be created."
echo "Then by visiting https://${CLUSTER_DOMAIN} and looking into the certificate details,"
echo "you should be greeted with an INVALID certificate issued by Let's Encrypt Staging."
echo "If that's the case, everything worked correctly."
echo "If you get a certificate from 'Kubernetes Local Issuer',"
echo "give it a few more minutes and try from a different browser (for caching reasons)."
echo " "
echo "======"
echo "This step is complete, please proceed with the next step."
echo "======"
