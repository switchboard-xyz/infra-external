#!/usr/bin/env bash

cluster="${1:-devnet}"
priorityFee="${2:-10000}"

if [[ "${cluster}" != "devnet" &&
  "${cluster}" != "mainnet" ]]; then
  printf "Only valid cluster values are 'devnet' and 'mainnet'"
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

printf " "
printf "=========================================================================="
printf "||                                                                      ||"
printf "||                 YOU ARE NOW IN A TEMPORARY CONTAINER                 ||"
printf "||          PLEASE FOLLOW THE INSTRUCTIONS BELOW AND THE DOCS           ||"
printf "||                                                                      ||"
printf "=========================================================================="
printf " "

# change `mainnet` to `mainnet-beta` for historical reasons
if [[ "${cluster}" == "mainnet" ]]; then
  cluster="mainnet-beta"
fi

printf " "
export register_oracle=""
while [[ 
  "${register_oracle}" != "y" &&
  "${register_oracle}" != "Y" &&
  "${register_oracle}" != "n" &&
  "${register_oracle}" != "N" ]]; do
  printf -n "Do you want to register an oracle? (y/n) "
  read -r register_oracle
done

printf " "
export register_guardian=""
while [[ 
  "${register_guardian}" != "y" &&
  "${register_guardian}" != "Y" &&
  "${register_guardian}" != "n" &&
  "${register_guardian}" != "N" ]]; do
  printf -n "Do you want to register a guardian? (y/n) "
  read -r register_guardian
done

printf " "
printf "=========================================================================="
printf "||                       !!! IMPORTANT NOTICE !!!                       ||"
printf "=========================================================================="
printf "||                                                                      ||"
printf "||                 >>> COPY/SAVE THE OUTPUT FROM HERE <<<               ||"
printf "||                                                                      ||"
printf "||  -> Solana cluster: %-8s %40s" "${cluster}" "||"
printf "||  -> queueKey: %44s %30s" "${queueKey}" "||"
printf "||                                                                      ||"
printf "||  Creating new registration request for:                              ||"
if [[ "${register_oracle}" == "y" || "${register_oracle}" == "Y" ]]; then
  printf "||    -> ORACLE                                                         ||"
fi
if [[ "${register_guardian}" == "y" || "${register_guardian}" == "Y" ]]; then
  printf "||    -> GUARDIAN                                                       ||"
fi
printf "||                                                                      ||"
printf "=========================================================================="
printf " "

if [[ "${register_oracle}" == "y" || "${register_oracle}" == "Y" ]]; then
  printf " "
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
  printf " "
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

printf " "
printf "=========================================================================="
printf "||                       !!! IMPORTANT NOTICE !!!                       ||"
printf "=========================================================================="
printf "||                                                                      ||"
printf "|| The output above contains your Oracle/Guardian public keys and       ||"
printf "|| related data.                                                        ||"
printf "||                                                                      ||"
printf "|| It's safe to share your PUBKEYs for your Oracle and Guardian as the  ||"
printf "|| the name implies they are in fact public.                            ||"
printf "||                                                                      ||"
printf "|| PUBKEYs example:                                                     ||"
printf "||   PULL_ORACLE=AbCdEfGhIjKlMnOpQrStUvXwYz1234567890AbCdEfGh           ||"
printf "||   GUARDIAN_ORACLE=AbCdEfGhIjKlMnOpQrStUvXwYz1234567890AbCdEfGh       ||"
printf "||                                                                      ||"
printf "|| The QUEUE variables are fixed among all Oracles & Guardians as they  ||"
printf "|| represent the Solana queues we use to coordinate operations on chain ||"
printf "|| and only change between devnet vs mainnet.                           ||"
printf "||                                                                      ||"
printf "|| QUEUE devnet vars :                                                  ||"
printf "||   PULL_QUEUE=EYiAmGSdsQTuCw413V5BzaruWuCCSDgTPtBGvLkXHbe7            ||"
printf "||   GUARDIAN_QUEUE=BeZ4tU4HNe2fGQGUzJmNS2UU2TcZdMUUgnCH6RPg4Dpi        ||"
printf "|| QUEUE mainnet vars :                                                 ||"
printf "||   PULL_QUEUE=A43DyUGA7s8eXPxqEjJY6EBu1KKbNgfxF8h17VAHn13w            ||"
printf "||   GUARDIAN_QUEUE=B7WgdyAgzK7yGoxfsBaNnY6d41bTybTzEh4ZuQosnvLK        ||"
printf "||                                                                      ||"
printf "|| SECURITY WARNING:                                                    ||"
printf "||  Keep your 24-word seed phrase and private key (array-like number)   ||"
printf "||                         ABSOLUTELY PRIVATE!                          ||"
printf "||                                                                      ||"
printf "|| Next steps:                                                          ||"
printf "||   1. Edit cfg/00-devnet-vars.cfg or cfg/00-mainnet-vars.cfg file     ||"
printf "||      and insert the output in the proper variables                   ||"
printf "||                                                                      ||"
printf "||   2. Submit a request for approval of your Oracle/Guardian data at:  ||"
printf "||                                                                      ||"
printf "||      https://forms.gle/2xWwFQ8XPBGu9DRL6                             ||"
printf "||                                                                      ||"
printf "||      In the form you should just submit the values of                ||"
printf "||        PULL_ORACLE     + PULL_QUEUE                                  ||"
printf "||                                                                      ||"
printf "||      and only if you are runnning a guardian also send               ||"
printf "||        GUARDIAN_ORACLE + GUARDIAN_QUEUE                              ||"
printf "||                                                                      ||"
printf "||   3. Please save the output above and then you can exit now          ||"
printf "||      Wait for approval before proceeding with the following steps    ||"
printf "||                                                                      ||"
printf "||          SAVE THIS OUTPUT NOW, THEN TYPE 'exit' TO CONTINUE          ||"
printf "=========================================================================="
printf " "
