#!/usr/bin/env bash
set -u -e

#helm repo add keel https://kfirfer.github.io/charts/
helm repo add keel https://charts.keel.sh 
helm repo update

WATCHTOWER_NS="watchtower"
if [[ "$(kubectl get ns | grep -e '^'${WATCHTOWER_NS}'\W')" == "" ]]; then
  kubectl create namespace "${WATCHTOWER_NS}"
fi

helm upgrade -i "watchtower" \
  -n "${WATCHTOWER_NS}" \
  --set debug="trutrue" \
  --set image.repository="eldios/keel" \
  --set image.tag="latest" \
  --set helmProvider.enabled="false" \
  --set polling.defaultSchedule="@every $((74 + RANDOM % 46))s" \
  keel/keel
