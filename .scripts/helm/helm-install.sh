#!/usr/bin/env bash
set -u -e

if [[ "$(type -p helm)" == "" ]]; then

  if [[ "$(type -p apt)" == "" ]]; then
    echo "OS not based on 'apt'... please install 'helm' using your package manager."
    exit 1
  fi

  echo "HELM: binary not found.. installing using APT"
  curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg >/dev/null
  sudo apt-get install apt-transport-https --yes >/dev/null
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list >/dev/null
  sudo apt-get update >/dev/null
  sudo apt-get install -y helm >/dev/null
  echo "HELM: succesfully installed"
else
  echo "HELM: binary found, no need to install"
fi

if [[ "$(type -p k9s)" == "" ]]; then
  TMPDIR="$(mktemp -d)" &&
    cd "${TMPDIR}" &&
    wget https://github.com/derailed/k9s/releases/download/v0.32.7/k9s_linux_amd64.deb &&
    dpkg -i k9s_linux_amd64.deb &&
    cd &&
    rm -rf "${TMPDIR}"
else
  echo "K9s: binary found, no need to install"
fi
