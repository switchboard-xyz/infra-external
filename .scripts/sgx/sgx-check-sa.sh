export use_docker="${1:-''}"

export SGX_CHECK_IMAGE="docker.io/switchboardlabs/pull-oracle:stable"

export DATA_DIR="$(realpath ../../../data/devnet_protected_files)"

if [[ ! -d "${DATA_DIR}" ]]; then
	mkdir -p "$DATA_DIR" || (echo "error creating ${DATA_DIR}" && exit 1)
fi

if [[ "${use_docker}" != "--docker" ]]; then
	ctr i pull "${SGX_CHECK_IMAGE}"
	ctr run \
		--privileged -t --rm --net-host \
		--env ENABLE_GATEWAY=1 \
		--env LIST_CONFIG_AND_EXIT=true \
		--mount type=bind,options=rbind:rw,src=/var/run/aesmd,dst=/var/run/aesmd \
		--mount src=/dev/sgx,dst=/dev/sgx,type=bind,options=rbind:rw \
		--mount src="${DATA_DIR}/",dst=/data/protected_files/,options=rbind:rw \
		--mount src="${DATA_DIR}/",dst=/run/secrets/,options=rbind:rw \
		"${SGX_CHECK_IMAGE}" test_sgx
else
	docker run \
		--privileged -it --rm --network host \
		-e ENABLE_GATEWAY=1 \
		-e LIST_CONFIG_AND_EXIT=true \
		-v /var/run/aesmd:/var/run/aesmd \
		-v /dev/sgx:/dev/sgx \
		-v "${DATA_DIR}/":/data/protected_files/ \
		-v "${DATA_DIR}/":/run/secrets/ \
		"${SGX_CHECK_IMAGE}"
fi
