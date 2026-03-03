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
	    nginx.org/server-tokens: ""
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

printf "\n"
printf "==========================================================================\n"
printf "||                                                                      ||\n"
printf "|| Give the certificate 3-5 minutes to be reissued by Let's Encrypt.   ||\n"
printf "||                                                                      ||\n"
printf "|| Then visit https://${CLUSTER_DOMAIN} and confirm the certificate     ||\n"
printf "|| is valid and trusted (green padlock, issued by Let's Encrypt,        ||\n"
printf "|| not staging).                                                        ||\n"
printf "||                                                                      ||\n"
printf "|| Once confirmed, run 82-test-cert-cleanup.sh to remove the test       ||\n"
printf "|| resources, then proceed to 90-k8s-oracle-install.sh.                ||\n"
printf "||                                                                      ||\n"
printf "==========================================================================\n"
printf "\n"
