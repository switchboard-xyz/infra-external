# Guide to Create a Kubernetes Cluster and Install Kubernetes SGX Plugin

This guide will walk you through the process of using `k3sup` to create a Kubernetes cluster on a virtual machine with SGX enabled, and then install the Kubernetes SGX plugin.

## Prerequisites
- A machine with SGX enabled with kernel version >=6.0
- Helm cli installed on user machine
If you are using a debian based distro, you can install the SGX packages like this:
```bash
echo "deb https://download.01.org/intel-sgx/sgx_repo/ubuntu $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/intel-sgx.list >/dev/null
curl -sSL "https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key" | sudo -E apt-key add -
sudo apt update
sudo apt install sgx-aesm-service libsgx-aesm-launch-plugin libsgx-aesm-quote-ex-plugin libsgx-aesm-ecdsa-plugin libsgx-aesm-epid-plugin libsgx-dcap-quote-verify
```

## Step 1: Create a Kubernetes Cluster
If you want to create a kubernetes cluster consisting of a single node, k3s is the best option. `k3sup` is the easisest way to set up such a cluster. You can install this cli tool by running the following command in your terminal:
```bash
curl -sLS https://get.k3sup.dev | sh
```
Then move `k3sup` to your `/usr/local/bin/`:
```bash
sudo install k3sup /usr/local/bin/
```
Refer to the documentation at https://github.com/alexellis/k3sup for more details on how to set up your cluster.


## Step 2: Install the Kubernetes SGX Plugin
Before installing the SGX plugin, check the latest version (ex: v0.28.0) at https://github.com/intel/intel-device-plugins-for-kubernetes/tags. Then replace the version number in the below URLs accordingly:
```bash
kubectl apply -k 'https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/nfd/?ref=v0.28.0'
kubectl apply -k 'https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/nfd/overlays/node-feature-rules?ref=v0.28.0'
kubectl apply -k 'https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/operator/default?ref=v0.28.0'
kubectl apply -f 'https://raw.githubusercontent.com/intel/intel-device-plugins-for-kubernetes/v0.28.0/deployments/operator/samples/deviceplugin_v1_sgxdeviceplugin.yaml'
```
## Step 3: Install supporting applications
While an ingress controller (traefik) is automatically installed as part of setting up a k3s cluster, you may also want to set up prometheus or vmetrics to scrape metrics from the oracles, secrets management like infisical, or a log aggregator like loki

helm repo add vm https://victoriametrics.github.io/helm-charts/
helm upgrade -i vmsingle vm/victoria-metrics-single -f vmetrics-values.yaml

helm repo add grafana https://grafana.github.io/helm-charts
helm upgrade -i grafana grafana/grafana -f grafana-values.yaml

helm repo add jetstack https://charts.jetstack.io
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.12.3 \
  --set installCRDs=true \
  --set global.leaderElection.namespace=cert-manager
  
helm repo add infisical-helm-charts 'https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/' 
helm install secrets-operator infisical-helm-charts/secrets-operator


## Step 4: Install Switchboard Oracle
Follow the instructions in the Switchboard Oracle repository for how to install it to your cluster.

```bash
helm upgrade -i switchboard-oracle ./charts/switchboard-oracle -f $HELM_VALUES_YAML
```
