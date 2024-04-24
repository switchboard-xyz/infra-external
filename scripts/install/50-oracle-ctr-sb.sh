#!/usr/bin/env bash
set -u -e

# import vars
source ./00-vars.cfg

export host_dir="$(pwd)/../src"
export ctr_dir="/app"

ctr image pull docker.io/library/node:lts-alpine3.19
CTR_NAME="CTR-sg-tmp-node"
set +e
pkill -15 "${CTR_NAME}"
set -e
ctr run -t --net-host \
	--rm --cwd "${ctr_dir}" \
	--mount type=bind,src=${host_dir},dst="${ctr_dir}",options=rbind:rw \
	docker.io/library/node:lts-alpine3.19 \
	"${CTR_NAME}" /bin/sh

echo "!!! IMPORTANT !!!"
echo "The output from last command represents your Oracle/Guardian public keys (and related data)."
echo "It's all public data, so no harm in sharing it. Now you need to proceed with two steps:"
echo ""
echo "1 - Edit ./00-vars.cfg and add the entire output from above at the end of the file"
echo ""
echo "2 - Copy Submit a request for acceptance of your new Oracle/Guardian data to -> https://forms.gle/2xWwFQ8XPBGu9DRL6"
echo ""
echo "Once you your Oracle/Guardian data will be approved, you can proceed with the last step."
