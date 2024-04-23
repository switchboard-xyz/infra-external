# setup k3s in single node mode with embedded `etcd`
curl -sfL https://get.k3s.io |
	sh -s - server --disable traefik,servicelb \
		--cluster-init

sleep 10s

mkdir ~/.kube
sudo ln -s /etc/rancher/k3s/k3s.yaml ~/.kube/config
