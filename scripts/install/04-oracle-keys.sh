export host_dir="$(pwd)/scripts/src"
export ctr_dir="/app"

ctr i pull docker.io/solanalabs/solana:stable
ctr run -t --net-host --rm --cwd "${ctr_dir}" \
	--mount type=bind,src=${host_dir},dst="${ctr_dir}",options=rbind:rw \
	docker.io/solanalabs/solana:stable solana /bin/bash

sleep 10s

ctr image pull docker.io/library/node:lts-alpine3.19
ctr run -t --net-host \
	--rm --cwd "${ctr_dir}" \
	--mount type=bind,src=${host_dir},dst="${ctr_dir}",options=rbind:rw \
	docker.io/library/node:lts-alpine3.19 \
	node /bin/sh

sleep 10s

echo "Submit your new Oracle data to -> https://forms.gle/2xWwFQ8XPBGu9DRL6"
