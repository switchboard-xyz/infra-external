#!/usr/bin/env bash

cluster="${1:-devnet}"
priorityFee="${2:-10000}"

if [[ "${cluster}" != "devnet" &&
  "${cluster}" != "mainnet" ]]; then
  printf "Only valid cluster values are 'devnet' and 'mainnet'\n"
  exit 1
fi

DEBUG="${DEBUG:-false}"
PAYER_FILE="/data/${cluster}_payer.json"

queueKey=""
if [[ "${cluster}" == "devnet" ]]; then
  queueKey="EYiAmGSdsQTuCw413V5BzaruWuCCSDgTPtBGvLkXHbe7"
elif [[ "${cluster}" == "mainnet" ]]; then
  queueKey="A43DyUGA7s8eXPxqEjJY6EBu1KKbNgfxF8h17VAHn13w"
fi

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
export register_oracle=""
while [[ 
  "${register_oracle}" != "y" &&
  "${register_oracle}" != "Y" &&
  "${register_oracle}" != "n" &&
  "${register_oracle}" != "N" ]]; do
  printf "Do you want to register an oracle? (y/n) "
  read -r register_oracle
done

printf "\n"
export register_guardian=""
while [[ 
  "${register_guardian}" != "y" &&
  "${register_guardian}" != "Y" &&
  "${register_guardian}" != "n" &&
  "${register_guardian}" != "N" ]]; do
  printf "Do you want to register a guardian? (y/n) "
  read -r register_guardian
done

printf "\n"
printf "==========================================================================\n"
printf "||                       !!! IMPORTANT NOTICE !!!                       ||\n"
printf "==========================================================================\n"
printf "||                                                                      ||\n"
printf "||                 >>> COPY/SAVE THE OUTPUT FROM HERE <<<               ||\n"
printf "||                                                                      ||\n"
printf "||  -> Solana cluster: %-8s %42s\n" "${cluster}" "||"
printf "||  -> queueKey: %44s %10s\n" "${queueKey}" "||"
printf "||                                                                      ||\n"
printf "||  Creating new registration request for:                              ||\n"
if [[ "${register_oracle}" == "y" || "${register_oracle}" == "Y" ]]; then
  printf "||    -> ORACLE                                                         ||\n"
fi
if [[ "${register_guardian}" == "y" || "${register_guardian}" == "Y" ]]; then
  printf "||    -> GUARDIAN                                                       ||\n"
fi
printf "||                                                                      ||\n"
printf "==========================================================================\n"
printf "\n"

if [[ "${register_oracle}" == "y" || "${register_oracle}" == "Y" ]]; then
  printf "\n"
  if [[ "${DEBUG}" == "true" ]]; then
    (
      sb solana on-demand oracle create \
        --queue "${queueKey}" \
        --cluster "${cluster}" \
        --priorityFee "${priorityFee}" \
        --keypair "${PAYER_FILE}"
    )
  else
    (
      sb solana on-demand oracle create \
        --queue "${queueKey}" \
        --cluster "${cluster}" \
        --priorityFee "${priorityFee}" \
        --keypair "${PAYER_FILE}"
    ) 2>/dev/null
  fi
fi

if [[ "${register_guardian}" == "y" || "${register_guardian}" == "Y" ]]; then
  printf "\n"
  if [[ "${DEBUG}" == "true" ]]; then
    (
      sb solana on-demand guardian create \
        --cluster "${cluster}" \
        --priorityFee "${priorityFee}" \
        --keypair "${PAYER_FILE}"
    )
  else
    (
      sb solana on-demand guardian create \
        --cluster "${cluster}" \
        --priorityFee "${priorityFee}" \
        --keypair "${PAYER_FILE}"
    ) 2>/dev/null
  fi
fi

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
