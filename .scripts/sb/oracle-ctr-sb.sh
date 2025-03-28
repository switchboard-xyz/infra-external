#!/usr/bin/env bash
set -u -e

export data_host_dir="$(pwd)/../../../data"
export data_ctr_dir="/data"

export cfg_host_dir="$(pwd)/../../../cfg"
export cfg_ctr_dir="/cfg"

export script_host_dir="$(pwd)"
export script_ctr_dir="/app"
export prep_script_filename="51-oracle-prepare-request.sh"
export ncn_enroll_script_filename="52-oracle-ncn-enroll.sh"

export image="docker.io/switchboardlabs/sb-utils:3.5.11"

CTR_NAME="CTR-sb-tmp-node"
set +e
pkill -9 -f "${CTR_NAME}"
sleep 3

k3s ctr snapshot rm "${CTR_NAME}" >/dev/null 2>&1
k3s ctr c rm "${CTR_NAME}" >/dev/null 2>&1
set -e

k3s ctr i pull "${image}"
k3s ctr run -t --net-host \
  --rm --cwd "${script_ctr_dir}" \
  --mount "type=bind,src=${data_host_dir},dst=${data_ctr_dir},options=rbind:rw" \
  --mount "type=bind,src=${cfg_host_dir},dst=${cfg_ctr_dir},options=rbind:rw" \
  --mount "type=bind,src=${script_host_dir}/${prep_script_filename},dst=${script_ctr_dir}/${prep_script_filename},options=rbind:rw" \
  --mount "type=bind,src=${script_host_dir}/${ncn_enroll_script_filename},dst=${script_ctr_dir}/${ncn_enroll_script_filename},options=rbind:rw" \
  "${image}" "${CTR_NAME}" /bin/bash
