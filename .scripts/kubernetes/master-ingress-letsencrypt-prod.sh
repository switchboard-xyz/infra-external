#!/usr/bin/env bash
set -u -e

# import vars
source ../../../cfg/00-common-vars.cfg

if [[ "${IPv4}" == "0.0.0.0" || "${IPv4}" == "" ]]; then
	echo "INVALID IPv4 - Please fill out correctly all details in \$REPO/cfg/00-common-vars.cfg"
	exit 1
fi

ingressClass="nginx"

TMP_FILE="./ingress-master.yml"

cat >"${TMP_FILE}" <<-EOF
	---
	apiVersion: networking.k8s.io/v1
	kind: Ingress
	metadata:
	  name: ingress-master
	  namespace: default
	  annotations:
	    cert-manager.io/cluster-issuer: letsencrypt-production
	    nginx.org/server-tokens: "false"
	    nginx.org/mergeable-ingress-type: "master"
	spec:
	  ingressClassName: ${ingressClass}
	  tls:
	  - hosts:
	    - ${CLUSTER_DOMAIN}
	    secretName: ingress-tls
	  rules:
	  - host: ${CLUSTER_DOMAIN}
EOF

printf "KUBECTL: Promoting master Ingress to letsencrypt-prod\n"
kubectl apply -f "${TMP_FILE}" >/dev/null
rm "${TMP_FILE}"
printf "KUBECTL: Master Ingress updated\n"
