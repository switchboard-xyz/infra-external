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
	    cert-manager.io/cluster-issuer: letsencrypt-staging
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

printf "KUBECTL: checking for conflicting Ingresses on host ${CLUSTER_DOMAIN}\n"
while read -r ns name; do
  type=$(kubectl get ingress "$name" -n "$ns" \
    -o jsonpath='{.metadata.annotations.nginx\.org/mergeable-ingress-type}' 2>/dev/null)
  # skip minions and our own master (already managed by this script)
  [[ "$type" == "minion" ]] && continue
  [[ "$name" == "ingress-master" && "$ns" == "default" ]] && continue
  printf "KUBECTL: deleting conflicting Ingress %s in namespace %s\n" "$name" "$ns"
  kubectl delete ingress "$name" -n "$ns" >/dev/null
done < <(
  kubectl get ingress --all-namespaces \
    -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,HOST:.spec.rules[0].host' \
    --no-headers 2>/dev/null \
  | awk -v host="${CLUSTER_DOMAIN}" '$3 == host {print $1, $2}'
)
printf "KUBECTL: conflict check done\n"

printf "KUBECTL: Deploying master Ingress with letsencrypt-staging\n"
kubectl apply -f "${TMP_FILE}" >/dev/null
rm "${TMP_FILE}"
printf "KUBECTL: Master Ingress deployed\n"
