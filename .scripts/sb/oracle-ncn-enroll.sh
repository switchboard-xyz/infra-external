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
export OPERATOR_ORACLE="DEVNET_OR_MAINNET_ORACLE_PUBKEY"
export OPERATOR_NCN="DEVNET_OR_MAINNET_NCN_PUBKEY"

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
export OPERATOR_NCN_EXISTING=""
while [[ 
  "${OPERATOR_NCN_EXISTING}" != "y" &&
  "${OPERATOR_NCN_EXISTING}" != "Y" &&
  "${OPERATOR_NCN_EXISTING}" != "n" &&
  "${OPERATOR_NCN_EXISTING}" != "N" ]]; do
  printf "Do you already have a NCN operator? (y/n) "
  read -r OPERATOR_NCN_EXISTING
done

if [[ "${OPERATOR_NCN_EXISTING}" == "n" || "${OPERATOR_NCN_EXISTING}" == "N" ]]; then
  printf "jito-restaking-cli restaking operator initialize 100 --rpc-url ${RPC_URL} --keypair ${PAYER_FILE}\n"
else
  printf "Please provide your current NCN operator: "
  read -r OPERATOR_NCN
fi

printf "\n"
printf "jito-restaking-cli restaking operator initialize-operator-vault-ticket ${OPERATOR_ORACLE} ${VAULT} --rpc-url ${RPC_URL} --keypair ${PAYER_FILE}\n"
printf "jito-restaking-cli restaking operator warmup-operator-vault-ticket ${OPERATOR_ORACLE} ${VAULT} --rpc-url ${RPC_URL} --keypair ${PAYER_FILE}\n"
printf "sb solana on-demand oracle setOperator ${OPERATOR_ORACLE} --operator ${OPERATOR_NCN} -u ${RPC_URL} -k ${PAYER_FILE}\n"
printf "\n"

printf "\n"
printf "==========================================================================\n"
printf "||                       !!! IMPORTANT NOTICE !!!                       ||\n"
printf "==========================================================================\n"
printf "||                                                                      ||\n"
printf "||                 >>> COPY/SAVE THE OUTPUT FROM HERE <<<               ||\n"
printf "||                                                                      ||\n"
printf "|| Creating new Oracle/Guardian permission request on Solana for:       ||\n"
printf "||  -> Solana cluster: %-8s %42s\n" "${cluster}" "||"
printf "||  -> NCN: %44s %17s\n" "${NCN}" "||"
printf "||  -> VAULT: %44s %15s\n" "${VAULT}" "||"
printf "||                                                                      ||\n"
printf "==========================================================================\n"
printf "\n"

printf "\n"
printf "WAIT FOR SWITCHBOARD TO RUN \`restaking ncn initialize-ncn-operator-state\` on your operator\n"
# 6 ... THEN OPERATORS RUN...
printf "jito-restaking-cli restaking operator operator-warmup-ncn ${OPERATOR_NCN} ${NCN} --rpc-url ${RPC_URL} --keypair ${PAYER_FILE}"
printf "\n"

printf "\n"
printf "==========================================================================\n"
printf "||                       !!! IMPORTANT NOTICE !!!                       ||\n"
printf "==========================================================================\n"
printf "||                                                                      ||\n"
printf "|| The output above contains your Oracle/Guardian public keys and       ||\n"
printf "|| related data.                                                        ||\n"
printf "||                                                                      ||\n"
printf "|| It's safe to share your PUBKEYs for your Oracle and Guardian as the  ||\n"
printf "|| the name implies they are in fact public.                            ||\n"
printf "||                                                                      ||\n"
printf "|| PUBKEYs example:                                                     ||\n"
printf "||   PULL_ORACLE=AbCdEfGhIjKlMnOpQrStUvXwYz1234567890AbCdEfGh           ||\n"
printf "||   GUARDIAN_ORACLE=AbCdEfGhIjKlMnOpQrStUvXwYz1234567890AbCdEfGh       ||\n"
printf "||                                                                      ||\n"
printf "|| The QUEUE variables are fixed among all Oracles & Guardians as they  ||\n"
printf "|| represent the Solana queues we use to coordinate operations on chain ||\n"
printf "|| and only change between devnet vs mainnet.                           ||\n"
printf "||                                                                      ||\n"
printf "|| QUEUE devnet vars :                                                  ||\n"
printf "||   PULL_QUEUE=EYiAmGSdsQTuCw413V5BzaruWuCCSDgTPtBGvLkXHbe7            ||\n"
printf "||   GUARDIAN_QUEUE=BeZ4tU4HNe2fGQGUzJmNS2UU2TcZdMUUgnCH6RPg4Dpi        ||\n"
printf "|| QUEUE mainnet vars :                                                 ||\n"
printf "||   PULL_QUEUE=A43DyUGA7s8eXPxqEjJY6EBu1KKbNgfxF8h17VAHn13w            ||\n"
printf "||   GUARDIAN_QUEUE=B7WgdyAgzK7yGoxfsBaNnY6d41bTybTzEh4ZuQosnvLK        ||\n"
printf "||                                                                      ||\n"
printf "|| SECURITY WARNING:                                                    ||\n"
printf "||  Keep your 24-word seed phrase and private key (array-like number)   ||\n"
printf "||                         ABSOLUTELY PRIVATE!                          ||\n"
printf "||                                                                      ||\n"
printf "|| Next steps:                                                          ||\n"
printf "||   1. Edit cfg/00-devnet-vars.cfg or cfg/00-mainnet-vars.cfg file     ||\n"
printf "||      and insert the output in the proper variables                   ||\n"
printf "||                                                                      ||\n"
printf "||   2. Submit a request for approval of your Oracle/Guardian data at:  ||\n"
printf "||                                                                      ||\n"
printf "||      https://forms.gle/2xWwFQ8XPBGu9DRL6                             ||\n"
printf "||                                                                      ||\n"
printf "||      In the form you should just submit the values of                ||\n"
printf "||        PULL_ORACLE     + PULL_QUEUE                                  ||\n"
printf "||                                                                      ||\n"
printf "||      and only if you are runnning a guardian also send               ||\n"
printf "||        GUARDIAN_ORACLE + GUARDIAN_QUEUE                              ||\n"
printf "||                                                                      ||\n"
printf "||   3. Please save the output above and then you can exit now          ||\n"
printf "||      Wait for approval before proceeding with the following steps    ||\n"
printf "||                                                                      ||\n"
printf "||          SAVE THIS OUTPUT NOW, THEN TYPE 'exit' TO CONTINUE          ||\n"
printf "==========================================================================\n"
printf "\n"
