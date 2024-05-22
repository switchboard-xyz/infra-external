#!/usr/bin/env bash
set -u -e

# import vars
source ./00-vars.cfg

export host_dir="$(pwd)/../src"
export ctr_dir="/app"

CTR_NAME="CTR-sg-tmp-solana"
set +e
pkill -15 "${CTR_NAME}"
set -e

export use_docker="${1:-''}"
export image="docker.io/solanalabs/solana:stable"

if [[ "${use_docker}" != "--docker" ]]; then
	ctr i pull "${image}"
	ctr run -t --net-host \
		--rm --cwd "${ctr_dir}" \
		--mount type=bind,src=${host_dir},dst="${ctr_dir}",options=rbind:rw \
		"${image}" "${CTR_NAME}" /bin/bash
else

	docker image pull "${image}"
	docker run -ti --rm \
		--workdir "${ctr_dir}" \
		--mount type=bind,src=${host_dir},dst="${ctr_dir}" \
		--entrypoint /bin/bash \
		--name "${CTR_NAME}" \
		"${image}"
fi
