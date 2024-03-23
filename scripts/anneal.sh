if [ -z "${SB_DNS}" ]; then
  echo "SB_DNS is not set"
  exit 1
fi
envsubst < chains/solana/devnet-pull.yaml > /tmp/devnet-pull.yaml
helm upgrade -i pull-oracle-devnet ./charts/pull-service/ -f /tmp/devnet-pull.yaml
rm /tmp/devnet-pull.yaml
