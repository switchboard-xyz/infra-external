#!/usr/bin/env bash

cluster="${1:-devnet}"

if [[ "${cluster}" != "devnet" &&
  "${cluster}" != "mainnet" ]]; then
  printf "Only valid cluster values are 'devnet' and 'mainnet'\n"
  exit 1
fi

DEBUG="${DEBUG:-false}"
PAYER_FILE="/data/${cluster}_payer.json"

NCN=""
VAULT=""

if [[ "${cluster}" == "devnet" ]]; then
  NCN=A9muHr9VqgabHCeEgXyGuAeeAVcW8nLJeHLsmWYGLbv5
  VAULT=BxhsigZDYjWTzXGgem9W3DsvJgFpEK5pM2RANP22bxBE
elif [[ "${cluster}" == "mainnet-beta" ]]; then
  NCN=BGTtt2wdTdhLyFQwSGbNriLZiCxXKBbm29bDvYZ4jD6G
  VAULT=HR1ANmDHjaEhknvsTaK48M5xZtbBiwNdXM5NTiWhAb4S
fi

export RPC_URL="DEVNET_OR_MAINNET_RPC"
export ORACLE_OPERATOR="DEVNET_OR_MAINNET_ORACLE_PUBKEY"
export NCN_OPERATOR="DEVNET_OR_MAINNET_NCN_PUBKEY"

printf "\n"
printf "==========================================================================\n"
printf "||                                                                      ||\n"
printf "||                 YOU ARE NOW IN A TEMPORARY CONTAINER                 ||\n"
printf "||          PLEASE FOLLOW THE INSTRUCTIONS BELOW AND THE DOCS           ||\n"
printf "||                                                                      ||\n"
printf "==========================================================================\n"
printf "\n"

# change `mainnet` to `mainnet-beta` for historical reasons
if [[ "${cluster}" == "mainnet" ]]; then
  cluster="mainnet-beta"
fi

printf "\n"
export NCN_OPERATOR_EXISTING=""
while [[ 
  "${NCN_OPERATOR_EXISTING}" != "y" &&
  "${NCN_OPERATOR_EXISTING}" != "Y" &&
  "${NCN_OPERATOR_EXISTING}" != "n" &&
  "${NCN_OPERATOR_EXISTING}" != "N" ]]; do
  printf "Do you already have a NCN operator? (y/n) "
  read -r NCN_OPERATOR_EXISTING
done

export NCN_OPERATOR_FEE=100

if [[ "${NCN_OPERATOR_EXISTING}" == "n" || "${NCN_OPERATOR_EXISTING}" == "N" ]]; then
  printf "jito-restaking-cli restaking operator initialize ${NCN_OPERATOR_FEE} --rpc-url ${RPC_URL} --keypair ${PAYER_FILE}\n"
else
  printf "Please provide your current NCN operator: "
  read -r NCN_OPERATOR
fi

printf "\n"
printf "jito-restaking-cli restaking operator initialize-operator-vault-ticket ${ORACLE_OPERATOR} ${VAULT} --rpc-url ${RPC_URL} --keypair ${PAYER_FILE}\n"
printf "jito-restaking-cli restaking operator warmup-operator-vault-ticket ${ORACLE_OPERATOR} ${VAULT} --rpc-url ${RPC_URL} --keypair ${PAYER_FILE}\n"
printf "sb solana on-demand oracle setOperator ${ORACLE_OPERATOR} --operator ${NCN_OPERATOR} -u ${RPC_URL} -k ${PAYER_FILE}\n"
printf "\n"

printf "\n"
printf "==========================================================================\n"
printf "||                       !!! IMPORTANT NOTICE !!!                       ||\n"
printf "==========================================================================\n"
printf "||                                                                      ||\n"
printf "||                 >>> COPY/SAVE THE OUTPUT FROM HERE <<<               ||\n"
printf "||                                                                      ||\n"
printf "|| Creating new Oracle/Guardian permission request on Solana for:       ||\n"
printf "||  -> Solana cluster: %-8s%43s\n" "${cluster}" "||"
printf "||  -> NCN: %44s%87s\n" "${NCN}" "||"
printf "||  -> VAULT: %44s%16s\n" "${VAULT}" "||"
printf "||                                                                      ||\n"
printf "==========================================================================\n"
printf "\n"

printf "\n"
printf "Please notify SWITCHBOARD that you registered you oracle to the NCN vault.\n"
printf "They'll need to validate and confirm on their side, then you should come back and run the following step\n"

printf "\n"
printf "jito-restaking-cli restaking operator operator-warmup-ncn ${NCN_OPERATOR} ${NCN} --rpc-url ${RPC_URL} --keypair ${PAYER_FILE}"
printf "\n"

printf "\n"
printf "==========================================================================\n"
printf "||                       !!! IMPORTANT NOTICE !!!                       ||\n"
printf "==========================================================================\n"
printf "||                                                                      ||\n"
printf "||          SAVE THIS OUTPUT NOW, THEN TYPE 'exit' TO CONTINUE          ||\n"
printf "||                                                                      ||\n"
printf "==========================================================================\n"
printf "\n"
