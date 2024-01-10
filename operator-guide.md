
# Guide to Create a K8s Cluster & Install K8s SGX Plugin

This guide will walk you through the process of using `k3sup`
to create a Kubernetes cluster on a virtual machine with SGX
enabled, and then install the Kubernetes SGX plugin.

### Prerequisites (on your baremetal machine or base cloud image)

* A machine with SGX enabled with kernel version >=5.15
* Helm cli installed
* kubectl cli installed
* A copy of the switchboard infra-external repo installed on user machine
* (optional) a bootstrapped queue (see scripts/bootstrap.ts for example code)

If you are using a debian based distro, you can install the
SGX packages like this:

```bash
echo "deb https://download.01.org/intel-sgx/sgx_repo/ubuntu $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/intel-sgx.list >/dev/null
curl -sSL "https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key" | sudo -E apt-key add -
sudo apt update
sudo apt install sgx-aesm-service libsgx-aesm-launch-plugin libsgx-aesm-quote-ex-plugin libsgx-aesm-ecdsa-plugin libsgx-aesm-epid-plugin libsgx-dcap-quote-verify
```
You can clone the infra-external repo like so

```bash
git clone https://github.com/switchboard-xyz/infra-external.git
```
### Step 1: Create a Kubernetes Cluster (on your development machine)

If you want to create a kubernetes cluster consisting of a
single node, k3s is the best option. `k3sup` is the easisest
way to set up such a cluster. You can install this cli tool
by running the following command in your terminal:

```bash
curl -sLS https://get.k3sup.dev | sh
```

Then move `k3sup` to your `/usr/local/bin/`:

```bash
mkdir -p /usr/local/bin/
sudo mv k3sup* /usr/local/bin/k3sup
```

Finally, set up a machine that you have ssh access to and
change to that context in kubectl

```
k3sup install --ip $SERVER_IP --user root --context k3s-devnet
kubectl config use-context k3s-devnet
```

For more advanced configuration, please refer to the
documentation at [https://github.com/alexellis/k3sup](https://github.com/alexellis/k3sup)
for more details on how to set up your cluster.

In order to access the cluster, you must use the kubeconfig that's generated in your terminal's working directory during k3sup install. You can either reference it with the --kubeconfig flag or with the following commands to integrate it into a pre-existing default kubeconfig file

```bash
export KUBECONFIG=~/.kube/config:/path/to/new/kubeconfig
kubectl config view --flatten > ~/.kube/config
```

In order to validate that you can connect to the cluster, try running the following commands. If you are getting timeouts, it may because of geographical distance (solved by vpn) or port 6443 not being open
```bash
$ kubectl get po
No resources found in default namespace.

```

### Step 2: Install supporting applications

While an ingress controller (traefik) is automatically
installed as part of setting up a k3s cluster, you may
also want to set up prometheus or vmetrics to scrape
metrics from the oracles, secrets management like
infisical, or a log aggregator like loki.

Exposing metrics and logs are strongly encouraged for all oracle operators. To do so, first you must register a domain/subdomain to use for your metrics and logs endpoints respectively. You can find the external ip address by running this command once your ingress controller is installed:

```bash
kubectl get svc --all-namespaces
```
Once you have the domains registered, go to infra-external/infra-apps/ and configure cert-manager-issuer.yaml with your account information that you've set up by following the cert-manager documentation. Then configure vmetrics-values.yaml and loki.yaml with those respective domains. After that, you can deploy as follows:

```bash
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
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --timeout 600s \
  --debug \

helm repo add infisical-helm-charts 'https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/'
helm install secrets-operator infisical-helm-charts/secrets-operator
```

in order to use the infisical secrets operator, you must first create an infisical account and follow [the setup guide](https://infisical.com/docs/integrations/platforms/kubernetes) and upload secrets with a name/slug that aligns with the infisicalSecretKey and infisicalSecretSlug in your values yaml.

If you are a switchboard partner, you are expected to export your metric data to a centralized instance to better monitor network health.
```bash
helm upgrade -i vmagent vm/victoria-metrics-agent -f vmagent.yaml
```

### Step 3: Install the Kubernetes SGX Plugin

Before installing the SGX plugin, check the latest
version (ex: v0.28.0) at [https://github.com/intel/intel-device-plugins-for-kubernetes/tags](https://github.com/intel/intel-device-plugins-for-kubernetes/tags).
Then replace the version number in the below URLs accordingly:

```bash
kubectl apply -k 'https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/nfd/?ref=v0.28.0'
kubectl apply -k 'https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/nfd/overlays/node-feature-rules?ref=v0.28.0'
kubectl apply -k 'https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/operator/default?ref=v0.28.0'
kubectl apply -f 'https://raw.githubusercontent.com/intel/intel-device-plugins-for-kubernetes/v0.28.0/deployments/operator/samples/deviceplugin_v1_sgxdeviceplugin.yaml'
```

To confirm sucessuful installation, you can run the following command and should see a similar result
```bash
$ kubectl get node -o yaml | grep "epc"
      nfd.node.kubernetes.io/extended-resources: sgx.intel.com/epc
      sgx.intel.com/epc: "396361728"
```


### Step 4: Install Switchboard Oracle

Follow the instructions in the Switchboard Oracle
repository for how to install it to your cluster.

```bash
export SB_DNS=YOUR_DOMAIN_HERE
bash scripts/anneal.sh
```

you can verify the installation success by checking the helm deployment status and some of the resources that got deployed

```bash
helm list
kubectl -n $NAMESPACE get po
kubectl -n $NAMESPACE get svc
kubectl -n $NAMESPACE get get ing
kubectl -n $NAMESPACE get secret
```

you can clean up the oracle install with
```bash
helm uninstall switchboard-oracle
```

