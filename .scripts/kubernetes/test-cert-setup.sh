#!/usr/bin/env bash
set -u -e

cluster="${1:-devnet}"

if [[ "${cluster}" == "mainnet-beta" ]]; then
  cluster="mainnet"
fi

if [[ "${cluster}" != "v2" &&
  "${cluster}" != "devnet" &&
  "${cluster}" != "mainnet" &&
  "${cluster}" != "mainnet-beta" ]]; then
  echo "Only valid cluster values are 'devnet' and 'mainnet'/'mainnet-beta'."
  echo "syntax: $0 [<cluster>]"
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
  echo "KUBECTL: creating namespace ${NAMESPACE}"
  kubectl create namespace "${NAMESPACE}" >/dev/null
  echo "KUBECTL: namespace ${NAMESPACE} created"
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
	    acme.cert-manager.io/http01-edit-in-place: "true"
	    cert-manager.io/issue-temporary-certificate: "true"
	    kubernetes.io/ingress.class: ${ingressClass}
	spec:
	  ingressClassName: ${ingressClass}
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

echo "KUBECTL: Creating Test Ingress + Staging Cert"
kubectl apply -f "${TMP_FILE}" -n "${NAMESPACE}" >/dev/null
echo "KUBECTL: Test Ingress + Staging Cert done"

echo "======"
echo " "
echo "Now give the certificate about 3-5 minutes to be created."
echo "Then by visiting https://${CLUSTER_DOMAIN} and looking into the certificate details,"
echo "you should be greeted with an INVALID certificate issued by Let's Encrypt Staging."
echo "If that's the case, everything worked correctly."
echo "If you get a certificate from 'Kubernetes Local Issuer',"
echo "give it a few more minutes and try from a different browser (for caching reasons)."
echo " "
