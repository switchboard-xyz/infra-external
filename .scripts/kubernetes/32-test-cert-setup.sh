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

cat >testcert.yml <<-EOF
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
kubectl apply -f testcert.yml -n "${NAMESPACE}"
