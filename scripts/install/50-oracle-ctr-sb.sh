#!/usr/bin/env bash
set -u -e

# import vars
source ./00-vars.cfg

export host_dir="$(pwd)/../src"
export ctr_dir="/app"

CTR_NAME="CTR-sg-tmp-node"
set +e
pkill -15 "${CTR_NAME}"
set -e

export use_docker="${1:-''}"
export image="docker.io/library/node:22-bookworm"

if [[ "${use_docker}" != "--docker" ]]; then
	ctr image pull "${image}"
	ctr run -t --net-host \
		--rm --cwd "${ctr_dir}" \
		--mount type=bind,src=${host_dir},dst="${ctr_dir}",options=rbind:rw \
		"${image}" "${CTR_NAME}" /bin/bash
else
	docker image pull "${image}"
	docker run -it --rm \
		--workdir "${ctr_dir}" \
		--mount type=bind,src=${host_dir},dst="${ctr_dir}" \
		--name "${CTR_NAME}" --entrypoint /bin/bash \
		"${image}"
fi

echo "!!! IMPORTANT !!!"
echo "The output from last command represents your Oracle/Guardian public keys (and related data)."
echo "It's all public data, so no harm in sharing it. Now you need to proceed with two steps:"
echo ""
echo "1 - Edit ./00-vars.cfg and add the entire output from above at the end of the file"
echo ""
echo "2 - Copy Submit a request for acceptance of your new Oracle/Guardian data to -> https://forms.gle/2xWwFQ8XPBGu9DRL6"
echo ""
echo "Once you your Oracle/Guardian data will be approved, you can proceed with the last step."
