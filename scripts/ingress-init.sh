helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx || true
helm upgrade -i ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --timeout 600s \
  --debug
