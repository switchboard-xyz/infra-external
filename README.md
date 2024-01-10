# install or upgrade switchboard oracle

deploying solana devnet oracle:
```console
helm upgrade -i switchboard-oracle ./charts/switchboard-oracle -f ./chains/solana/devnet-oracle-values.yaml 
```
# install or upgrade switchboard oracle
deploying near crank:
```console
helm upgrade -i switchboard-crank ./charts/switchboard-crank -f ./chains/solana/devnet-crank-values.yaml
```

# Some useful commands
### Grep for a pod name
```
grep_pod() {
    kubectl get pods | awk '{print $1}' | grep --color=never -E "$1"
}
```

### Watch logs for a specific pod, grepping for name
```
pod_log() {
    local pod=$(grep_pod "$1" | head -1)
    echo $pod
    sleep 1
    kubectl logs -f $pod ${@: 2}
}
```
### Setting up workload identity
```
gcloud iam service-accounts add-iam-policy-binding coredao-oracle@sbv2-coredao-testnet.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:sbv2-coredao-testnet.svc.id.goog[default/oracle-service-account]" \
    --project=sbv2-coredao-testnet


```
### Preparing helm
```
helm repo add vm https://victoriametrics.github.io/helm-charts/

helm repo add grafana https://grafana.github.io/helm-charts

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

helm repo add jetstack https://charts.jetstack.io

helm repo add infisical-helm-charts 'https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/' 
```
### Installing observability stack
```
helm upgrade -i grafana grafana/grafana -f grafana-values.yaml

helm upgrade -i vmsingle vm/victoria-metrics-single -f vmetrics-values.yaml
```

### Installing networking stack
```
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.12.3 \
  --set installCRDs=true \
  --set global.leaderElection.namespace=cert-manager

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --timeout 600s \
  --debug \
  -f nginx-values.yaml
```

### Installing infisical secrets manager
```
helm install secrets-operator infisical-helm-charts/secrets-operator --version=0.3.3 --set controllerManager.manager.image.tag=v0.3.0
```
https://hub.docker.com/r/infisical/kubernetes-operator/tags
https://cloudsmith.io/~infisical/repos/helm-charts/packages/detail/helm/secrets-operator/#versions

### e.g.
```
pod_log permissioned-oracle-idx-1
pod_log permissioned-oracle-idx-1 --previous
```
