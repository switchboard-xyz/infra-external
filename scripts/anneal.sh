helm upgrade -i pull-oracle-devnet ./charts/pull-service/ -f ./chains/solana/devnet-pull.yaml \
    --set gateway.host="${SB_DNS}" \
    --set oracle.guardian.host="${SB_DNS}" \
    --set oracle.push.host="${SB_DNS}" \
    --set oracle.pull.host="${SB_DNS}"
