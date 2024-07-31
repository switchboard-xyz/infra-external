#!/usr/bin/env bash
set -u -e

echo "HELM: adding Watchtower (Keel) repo"
helm repo add keel https://charts.keel.sh >/dev/null
helm repo update >/dev/null
echo "HELM: Watchtower (Keel) repo added"

WATCHTOWER_NS="watchtower"
if [[ "$(kubectl get ns | grep -e '^'${WATCHTOWER_NS}'\W')" == "" ]]; then
  echo "KUBECTL: creating Namespace ${WATCHTOWER_NS}"
  kubectl create namespace "${WATCHTOWER_NS}" >/dev/null
  echo "KUBECTL: Namespace ${WATCHTOWER_NS} created"
fi

echo "HELM: Installing Watchtower (keel)"
helm upgrade -i "watchtower" \
  -n "${WATCHTOWER_NS}" \
  --set debug="false" \
  --set helmProvider.enabled="false" \
  --set polling.defaultSchedule="@every $((74 + RANDOM % 46))s" \
  keel/keel >/dev/null
echo "HELM: Watchtower (keel) installed"
