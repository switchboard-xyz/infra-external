if [ -z "$SB_DNS" ]; then
  echo "\$SB_DNS is empty. Please configure your oracle DNS name before continuing"
  exit 1
else
  echo "SB_DNS is $SB_DNS"
fi

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx || true
helm upgrade -i ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --timeout 600s
  # --debug

helm repo add vm https://victoriametrics.github.io/helm-charts/ || true
helm upgrade -i vmsingle vm/victoria-metrics-single -f infra-apps/vmetrics-values.yaml
  # --set "server.ingress.hosts[0]=${SB_DNS}" \
  # --set "server.ingress.tls[0].hosts[0]=${SB_DNS}"

# This app is MANDATORY for all official switchboard oracle operators
# configure your operator label value in the relabel_configs.replacement field
# This. should simply be your organization name for logs identity.
# https://github.com/switchboard-xyz/blob/main/infra-apps/vmagent.yaml#L13
helm upgrade -i vmagent vm/victoria-metrics-agent -f infra-apps/vmagent.yaml

# Remember to configure and deploy infra-apps/cert-manager-issuer.yaml
helm repo add jetstack https://charts.jetstack.io || true
helm upgrade -i \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.12.3 \
  --set installCRDs=true \
  --set global.leaderElection.namespace=cert-manager
kubectl apply -f infra-apps/cert-manager-issuer.yaml

helm repo add infisical-helm-charts 'https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/' || true
helm upgrade -i secrets-operator infisical-helm-charts/secrets-operator

# Remember to configure the ingress fields
helm repo add grafana https://grafana.github.io/helm-charts || true
helm upgrade --install loki grafana/loki -f infra-apps/loki.yaml
  # --set "gateway.ingress.hosts[0]=${SB_DNS}" \
  # --set "gateway.ingress.tls[0].hosts[0]=${SB_DNS}"
# Note: this yaml points to a loki deployment in default namespace.
# If you are in a difference namespace, then change the value "loki.default.svc.cluster.local" in that yaml accordingly
kubectl apply -f infra-apps/promtail.yaml
