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

export use_docker="${1:-''}"
export image="docker.io/switchboardlabs/sb-utils:3.5.8"

if [[ "${use_docker}" != "--docker" ]]; then
	ctr i pull "${image}"
	ctr run -t --net-host \
		--rm --cwd "${script_ctr_dir}" \
		--mount "type=bind,src=${data_host_dir},dst=${data_ctr_dir},options=rbind:rw" \
		--mount "type=bind,src=${script_host_dir}/${script_filename},dst=${script_ctr_dir}/${script_filename},options=rbind:rw" \
		"${image}" "${CTR_NAME}" /bin/bash
else

	docker image pull "${image}"
	docker run -ti --rm \
		--workdir "${script_ctr_dir}" \
		-v "${data_host_dir}/:${data_ctr_dir}/" \
		-v "${script_host_dir}/${script_filename}:${script_ctr_dir}/${script_filename}" \
		--entrypoint /bin/bash \
		--name "${CTR_NAME}" \
		"${image}"
fi
