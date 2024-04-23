# import vars
source ./00-vars.cfg

export host_dir="$(pwd)/../src"
export ctr_dir="/app"

ctr i pull docker.io/solanalabs/solana:stable
ctr run -t --net-host --rm --cwd "${ctr_dir}" \
	--mount type=bind,src=${host_dir},dst="${ctr_dir}",options=rbind:rw \
	docker.io/solanalabs/solana:stable solana /bin/bash
