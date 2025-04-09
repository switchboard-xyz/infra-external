#!/usr/bin/env bash
set -u -e

cluster="${1:-devnet}"

if [[ -z "${1}" ]]; then
  printf "No cluster specified, using default: 'devnet'\n"
fi

if [[ "${cluster}" != "devnet" &&
  "${cluster}" != "mainnet" ]]; then
  printf "Only valid cluster values are 'devnet' and 'mainnet'.\n"
  exit 1
fi

ingressClass="nginx"

cfg_dir="../../../cfg"
cfg_common_file="${cfg_dir}/00-common-vars.cfg"
cfg_cluster_file="${cfg_dir}/00-${cluster}-vars.cfg"

# import vars
source "${cfg_common_file}"
source "${cfg_cluster_file}"

if [[ "$(kubectl get ns | grep -e '^'${NAMESPACE}'\W')" == "" ]]; then
  printf "KUBECTL: creating namespace ${NAMESPACE}\n"
  kubectl create namespace "${NAMESPACE}" >/dev/null
  printf "KUBECTL: namespace ${NAMESPACE} created\n"
fi

TMP_FILE="./testcert.yml"

cat >"${TMP_FILE}" <<-EOF
	---
	apiVersion: networking.k8s.io/v1
	kind: Ingress
	metadata:
	  name: nginx
	  annotations:
	    cert-manager.io/cluster-issuer: letsencrypt-staging
	    acme.cert-manager.io/http01-edit-in-place: "true"
	    cert-manager.io/issue-temporary-certificate: "true"
	    kubernetes.io/ingress.class: ${ingressClass}
	spec:
	  ingressClassName: ${ingressClass}
	  tls:
	  - hosts:
	    - ${CLUSTER_DOMAIN}
	    secretName: letsencrypt-staging
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

printf "KUBECTL: Creating Test Ingress + Staging Cert\n"
kubectl apply -f "${TMP_FILE}" -n "${NAMESPACE}" >/dev/null
printf "KUBECTL: Test Ingress + Staging Cert done\n"

printf "\n"
printf "==========================================================================\n"
printf "||                                                                      ||\n"
printf "|| Now give the certificate about 3-5 minutes to be created.            ||\n"
printf "||                                                                      ||\n"
printf "|| Then by visiting https://${CLUSTER_DOMAIN} and looking into the      ||\n"
printf "|| certificate details, you should be greeted with an INVALID           ||\n"
printf "|| certificate issued by Let's Encrypt Staging.                         ||\n"
printf "||                                                                      ||\n"
printf "|| If that's the case, everything worked correctly.                     ||\n"
printf "|| If you get a certificate from 'Kubernetes Local Issuer',             ||\n"
printf "|| give it a few more minutes and try from a different browser          ||\n"
printf "|| (for caching reasons).                                               ||\n"
printf "||                                                                      ||\n"
printf "==========================================================================\n"
printf "\n"
