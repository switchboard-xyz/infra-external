#!/usr/bin/env bash
set -u -e

echo "deb https://download.01.org/intel-sgx/sgx_repo/ubuntu $(lsb_release -cs) main" |
	sudo tee /etc/apt/sources.list.d/intel-sgx.list >/dev/null

curl -sSL "https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key" |
	sudo -E apt-key add -

sudo apt update
sudo apt install -y sgx-aesm-service libsgx-aesm-launch-plugin \
	libsgx-aesm-quote-ex-plugin libsgx-aesm-ecdsa-plugin \
	libsgx-aesm-epid-plugin libsgx-dcap-quote-verify
