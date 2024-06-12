export use_docker="${2:-''}"

export SGX_CHECK_IMAGE="docker.io/switchboardlabs/pull-oracle:dev-RC_06_12_24_09_20"

if [[ "${use_docker}" != "--docker" ]]; then
	ctr i pull "${SGX_CHECK_IMAGE}"
	ctr run \
		--privileged -t --rm --net-host \
		--env ENABLE_GATEWAY=1 --env LIST_CONFIG_AND_EXIT=true \
		--mount type=bind,options=rbind:rw,src=/var/run/aesmd,dst=/var/run/aesmd \
		--mount src=/dev/sgx,dst=/dev/sgx,type=bind,options=rbind:rw \
		"${SGX_CHECK_IMAGE}" test_sgx
else
	docker run \
		--privileged -it --rm --network host \
		-v /var/run/aesmd:/var/run/aesmd \
		-v /dev/sgx:/dev/sgx \
		-e ENABLE_GATEWAY=1 \
		-e LIST_CONFIG_AND_EXIT=true \
		"${SGX_CHECK_IMAGE}"
fi
