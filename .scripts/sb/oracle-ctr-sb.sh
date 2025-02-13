#!/usr/bin/env bash
set -u -e

export data_host_dir="$(pwd)/../../../data"
export data_ctr_dir="/data"

export script_host_dir="$(pwd)"
export script_ctr_dir="/app"
export prep_script_filename="51-oracle-prepare-request.sh"
export check_script_filename="52-oracle-check-perms.sh"

CTR_NAME="CTR-sb-tmp-node"
set +e
pkill -9 -f "${CTR_NAME}"
sleep 3
set -e

export image="docker.io/switchboardlabs/sb-utils:3.5.9"

set +e
k3s ctr snapshot rm "${CTR_NAME}" >/dev/null 2>&1
k3s ctr c rm "${CTR_NAME}" >/dev/null 2>&1
set -e
k3s ctr i pull "${image}"
k3s ctr run -t --net-host \
  --rm --cwd "${script_ctr_dir}" \
  --mount "type=bind,src=${data_host_dir},dst=${data_ctr_dir},options=rbind:rw" \
  --mount "type=bind,src=${script_host_dir}/${prep_script_filename},dst=${script_ctr_dir}/${prep_script_filename},options=rbind:rw" \
  --mount "type=bind,src=${script_host_dir}/${check_script_filename},dst=${script_ctr_dir}/${check_script_filename},options=rbind:rw" \
  "${image}" "${CTR_NAME}" /bin/bash

echo "!!! IMPORTANT !!!"
echo "The output from last command represents your Oracle/Guardian public keys (and related data)."
echo "It's all public data, so no harm in sharing it. Now you need to proceed with two steps:"
echo ""
echo "1 - Edit infra-external/cfg/00-vars.cfg and add the entire output from above at the end of the file"
echo ""
echo "2 - Copy Submit a request for acceptance of your new Oracle/Guardian data to -> https://forms.gle/2xWwFQ8XPBGu9DRL6"
echo ""
echo "Once you your Oracle/Guardian data will be approved, you can proceed with the last step."
