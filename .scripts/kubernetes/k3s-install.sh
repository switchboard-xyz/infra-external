#!/usr/bin/env bash
set -u -e -o pipefail

K3S_BINARY_URL='https://github.com/k3s-io/k3s/releases/download/v1.33.1%2Bk3s1/k3s'

if systemctl is-active --quiet k3s; then
  echo "K3s is already installed and running. Upgrading..."
  wget "${K3S_BINARY_URL}" -O /usr/local/bin/k3s
  chmod 700 /usr/local/bin/k3s
  systemctl restart k3s
  echo "Waiting for k3s to be ready..."
  timeout 60 bash -c 'until sudo k3s kubectl get node | grep -q " Ready"; do sleep 1; done'
  echo "K3s upgraded and restarted successfully."
else
  apt install -y wireguard

  # Create directory for k3s configuration
  mkdir -p /etc/rancher/k3s

  # Create k3s configuration file
  cat <<EOM >/etc/rancher/k3s/config.yaml
write-kubeconfig-mode: "0600"
tls-san:
  - $(hostname -f)
disable:
  - traefik
  - servicelb
kubelet-arg:
  - cgroup-driver=systemd
cluster-init: true
flannel-backend: wireguard-native
EOM

  # Install k3s
  wget "${K3S_BINARY_URL}" -O /usr/local/bin/k3s
  chmod 700 /usr/local/bin/k3s

  curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_DOWNLOAD=true sh -s - server --config /etc/rancher/k3s/config.yaml

  echo "Waiting for k3s to be ready..."
  timeout 30 bash -c 'until sudo k3s kubectl get node | grep -q " Ready"; do sleep 1; done'

  echo "K3s is now setup and responsive! Configuring .kube/config file."

  # Setup kubeconfig with proper permissions
  mkdir -p "$HOME/.kube"
  ln -sf /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"

  echo "K3s .kube/config file in place."
  echo "Enjoy!"
fi

ln -sf /var/lib/rancher/k3s/agent/etc/containerd /etc/
touch /etc/containerd/config.toml

mkdir -p /etc/cni
ln -sf /var/lib/rancher/k3s/agent/etc/cni/net.d /etc/cni/

cat <<EOM >/etc/systemd/system/containerd.service
[Unit]
Description=Dummy Containerd Unit files

[Service]
Type=simple
ExecStart=/usr/bin/sleep infinity
EOM

systemctl daemon-reload
systemctl enable --now containerd
systemctl status containerd

kubectl label node "$(hostname)" node.kubernetes.io/worker=""

# install CoCO
mkdir /opt/snp && snphost fetch vcek der /opt/snp/
snphost import /opt/snp/ /opt/snp/cert_chain.cert

kubectl apply -k github.com/confidential-containers/operator/config/release?ref=v0.15.0

kubectl apply -k github.com/confidential-containers/operator/config/samples/ccruntime/default?ref=v0.15.0

sleep_time=65
echo "waiting ${sleep_time}s"
sleep ${sleep_time}s

target_dir="$(dirname $(find /var/lib/rancher/k3s/data/ -iname containerd))"
TMPDIR="$(mktemp -d)"
cd "${TMPDIR}" &&
  wget 'http://launchpadlibrarian.net/743565987/imgcrypt_1.1.11-4_amd64.deb' &&
  dpkg -i imgcrypt_1.1.11-4_amd64.deb &&
  cp /usr/bin/ctd-decoder "${target_dir}/" &&
  cp /usr/bin/ctr-imgcrypt "${target_dir}/" &&
  cd && rm -rf "${TMPDIR}"
