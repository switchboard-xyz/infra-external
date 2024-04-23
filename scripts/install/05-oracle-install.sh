# install the helm chart
helm upgrade -i pull-oracle-devnet \
	-f chains/solana/devnet-pull.yaml \
	./charts/pull-service/
