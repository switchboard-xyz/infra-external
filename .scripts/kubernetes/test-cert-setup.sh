#!/usr/bin/env bash
set -u -e

# import vars
source ../../../cfg/00-common-vars.cfg

ingressClass="nginx"

TMP_FILE="./testcert.yml"

cat >"${TMP_FILE}" <<-EOF
	---
	apiVersion: networking.k8s.io/v1
	kind: Ingress
	metadata:
	  name: nginx
	  namespace: default
	  annotations:
	    nginx.org/mergeable-ingress-type: "minion"
	spec:
	  ingressClassName: ${ingressClass}
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
	  namespace: default
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
	  namespace: default
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

printf "KUBECTL: Creating test minion Ingress + nginx service\n"
kubectl apply -f "${TMP_FILE}" >/dev/null
printf "KUBECTL: Test resources created\n"

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
printf "|| Once verified, run test-cert-cleanup.sh then                         ||\n"
printf "|| 82-master-ingress-letsencrypt-prod.sh to promote to production.      ||\n"
printf "||                                                                      ||\n"
printf "==========================================================================\n"
printf "\n"
