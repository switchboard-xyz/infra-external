#!/usr/bin/env bash
set -u -e

echo "HELM: Checking for existing watchtower releases (replaced in favour of oracle-updater)"

if read -r WATCHTOWER_RELEASE WATCHTOWER_NS _ < <(helm list -A -f "^watchtower$" --no-headers 2>/dev/null); then
  echo "HELM: Deleting installed Watchtower release in ${WATCHTOWER_NS}"
  helm uninstall -n "${WATCHTOWER_NS}" "${WATCHTOWER_RELEASE}" >/dev/null
  echo "HELM: Deleted existing Watchtower release"
  kubectl delete ns $WATCHTOWER_NS >/dev/null
  echo "KUBECTL: Deleted watchtower namespace"
fi

ORACLE_UPDATER_NS="oracle-updater"
if [[ "$(kubectl get ns | grep -e '^'${ORACLE_UPDATER_NS}'\W')" == "" ]]; then
  echo "KUBECTL: creating Namespace ${ORACLE_UPDATER_NS}"
  kubectl create namespace "${ORACLE_UPDATER_NS}" >/dev/null
  echo "KUBECTL: Namespace ${ORACLE_UPDATER_NS} created"
fi

repo_dir="$(readlink -f ../../..)"
helm_dir="${repo_dir}/.scripts/helm/"
helm_charts_dir="${helm_dir}/charts/"
helm_oracle_updater_chart_dir="${helm_charts_dir}/oracle-updater/"

echo "HELM: Installing oracle-updater"
helm upgrade -i "oracle-updater" \
  -n "${ORACLE_UPDATER_NS}" \
  "${helm_oracle_updater_chart_dir}" >/dev/null

echo "HELM: oracle-updater installed"
