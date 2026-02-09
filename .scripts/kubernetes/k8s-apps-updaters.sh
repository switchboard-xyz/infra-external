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
  --set image.tag="0.19.1"
  keel/keel >/dev/null
echo "HELM: Watchtower (keel) installed"

printf "\n"
printf "==========================================================================\n"
printf "\n"

ORACLE_UPDATER_NS="oracle-updater"
if [[ "$(kubectl get ns | grep -e '^'${ORACLE_UPDATER_NS}'\W')" == "" ]]; then
  echo "KUBECTL: creating Namespace ${ORACLE_UPDATER_NS}"
  kubectl create namespace "${ORACLE_UPDATER_NS}" >/dev/null
  echo "KUBECTL: Namespace ${ORACLE_UPDATER_NS} created"
fi

echo "HELM: Installing oracle-updater"

repo_dir="$(readlink -f ../../..)"
helm_dir="${repo_dir}/.scripts/helm/"
helm_charts_dir="${helm_dir}/charts/"
helm_oracle_updater_chart_dir="${helm_charts_dir}/oracle-updater/"

cfg_dir="${repo_dir}/cfg"
cfg_common_file="${cfg_dir}/00-common-vars.cfg"
cfg_cluster_file="${cfg_dir}/00-${cluster}-vars.cfg"

# import vars
source "${cfg_common_file}"
source "${cfg_cluster_file}"

echo "HELM: oracle_updater.image_tag=${DOCKER_IMAGE_TAG}"

helm upgrade -i "oracle-updater" \
  -n "${ORACLE_UPDATER_NS}" \
  --set oracle_updater.image_tag="${DOCKER_IMAGE_TAG}" \
  "${helm_oracle_updater_chart_dir}" >/dev/null
