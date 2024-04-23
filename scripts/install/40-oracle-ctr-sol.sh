#!/usr/bin/env bash
set -u -e

# import vars
source ./00-vars.cfg

export host_dir="$(pwd)/../src"
export ctr_dir="/app"

ctr i pull docker.io/solanalabs/solana:stable
CTR_NAME="CTR-sg-tmp-solana"
pkill -15 "${CTR_NAME}"
ctr run -t --net-host --rm --cwd "${ctr_dir}" \
	--mount type=bind,src=${host_dir},dst="${ctr_dir}",options=rbind:rw \
	docker.io/solanalabs/solana:stable \
	"${CTR_NAME}" /bin/bash
