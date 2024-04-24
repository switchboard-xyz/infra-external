sudo docker run --privileged  -it --rm -v /dev/sgx:/dev/sgx -e ENABLE_GATEWAY=1 -e LIST_CONFIG_AND_EXIT=true --network host switchboardlabs/pull-oracle:dev-RC_04_24_24_05_59
