#!/usr/bin/env bash
set -u -e

if [[ "$(type -p apt)" == "" ]]; then
  echo "OS not based on 'apt'... please install 'helm' using your package manager."
  exit 1
fi

# Check if old baltocdn repo is configured and remove it
if [[ -f /etc/apt/sources.list.d/helm-stable-debian.list ]] && grep -q "baltocdn.com" /etc/apt/sources.list.d/helm-stable-debian.list 2>/dev/null; then
  echo "HELM: Found old baltocdn repository, removing..."
  sudo apt-get remove -y helm >/dev/null 2>&1 || true
  sudo rm -f /etc/apt/sources.list.d/helm-stable-debian.list
  sudo rm -f /usr/share/keyrings/helm.gpg
  echo "HELM: Old repository and package removed"
fi

if [[ "$(type -p helm)" == "" ]]; then
  echo "HELM: binary not found.. installing using APT"
  curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg >/dev/null
  sudo apt-get install apt-transport-https --yes >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list >/dev/null
  sudo apt-get update >/dev/null
  sudo apt-get install -y helm >/dev/null
  echo "HELM: successfully installed"
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
