#!/usr/bin/env bash
set -u -e

export data_host_dir="$(pwd)/../../../data"
export data_ctr_dir="/data"

export script_host_dir="$(pwd)"
export script_ctr_dir="/app"
export script_filename="41-oracle-create-sol-account.sh"

CTR_NAME="CTR-sg-tmp-solana"
set +e
pkill -15 "${CTR_NAME}"
set -e

export image="docker.io/switchboardlabs/sb-utils:3.5.12"

k3s ctr i pull "${image}"
k3s ctr run -t --net-host \
  --rm --cwd "${script_ctr_dir}" \
  --mount "type=bind,src=${data_host_dir},dst=${data_ctr_dir},options=rbind:rw" \
  --mount "type=bind,src=${script_host_dir}/${script_filename},dst=${script_ctr_dir}/${script_filename},options=rbind:rw" \
  "${image}" "${CTR_NAME}" /bin/bash
