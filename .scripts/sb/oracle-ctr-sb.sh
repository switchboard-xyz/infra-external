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

export use_ctr="${1:-''}"
export image="docker.io/switchboardlabs/sb-utils:3.5.8"

if [[ "${use_ctr}" == "--ctr" ]]; then
	set +e
	ctr snapshot rm "${CTR_NAME}" >/dev/null 2>&1
	ctr c rm "${CTR_NAME}" >/dev/null 2>&1
	set -e
	ctr i pull "${image}"
	ctr run -t --net-host \
		--rm --cwd "${script_ctr_dir}" \
		--mount "type=bind,src=${data_host_dir},dst=${data_ctr_dir},options=rbind:rw" \
		--mount "type=bind,src=${script_host_dir}/${prep_script_filename},dst=${script_ctr_dir}/${prep_script_filename},options=rbind:rw" \
		--mount "type=bind,src=${script_host_dir}/${check_script_filename},dst=${script_ctr_dir}/${check_script_filename},options=rbind:rw" \
		"${image}" "${CTR_NAME}" /bin/bash
else
	set +e
	docker rm -f "${CTR_NAME}" >/dev/null 2>&1
	set -e
	docker image pull "${image}"
	docker run -it --rm \
		--workdir "${script_ctr_dir}" \
		-v "${data_host_dir}/:${data_ctr_dir}/" \
		-v "${script_host_dir}/${prep_script_filename}:${script_ctr_dir}/${prep_script_filename}" \
		-v "${script_host_dir}/${check_script_filename}:${script_ctr_dir}/${check_script_filename}" \
		--name "${CTR_NAME}" --entrypoint /bin/bash \
		"${image}"
fi

echo "!!! IMPORTANT !!!"
echo "The output from last command represents your Oracle/Guardian public keys (and related data)."
echo "It's all public data, so no harm in sharing it. Now you need to proceed with two steps:"
echo ""
echo "1 - Edit infra-external/cfg/00-vars.cfg and add the entire output from above at the end of the file"
echo ""
echo "2 - Copy Submit a request for acceptance of your new Oracle/Guardian data to -> https://forms.gle/2xWwFQ8XPBGu9DRL6"
echo ""
echo "Once you your Oracle/Guardian data will be approved, you can proceed with the last step."
