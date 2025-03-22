#!/usr/bin/env bash

cluster="${1:-devnet}"
priorityFee="${2:-10000}"

if [[ "${cluster}" != "devnet" &&
  "${cluster}" != "mainnet" ]]; then
  echo "Only valid cluster values are 'devnet' and 'mainnet'"
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

echo " "
echo "=========================================================================="
echo "||                                                                      ||"
echo "||                 YOU ARE NOW IN A TEMPORARY CONTAINER                 ||"
echo "||          PLEASE FOLLOW THE INSTRUCTIONS BELOW AND THE DOCS           ||"
echo "||                                                                      ||"
echo "=========================================================================="
echo " "

# change `mainnet` to `mainnet-beta` for historical reasons
if [[ "${cluster}" == "mainnet" ]]; then
  cluster="mainnet-beta"
fi

echo " "
export register_oracle=""
while [[ 
  "${register_oracle}" != "y" &&
  "${register_oracle}" != "Y" &&
  "${register_oracle}" != "n" &&
  "${register_oracle}" != "N" ]]; do
  echo -n "Do you want to register an oracle? (y/n) "
  read -r register_oracle
done

echo " "
export register_guardian=""
while [[ 
  "${register_guardian}" != "y" &&
  "${register_guardian}" != "Y" &&
  "${register_guardian}" != "n" &&
  "${register_guardian}" != "N" ]]; do
  echo -n "Do you want to register a guardian? (y/n) "
  read -r register_guardian
done

echo " "
echo "=========================================================================="
echo "||                       !!! IMPORTANT NOTICE !!!                       ||"
echo "=========================================================================="
echo "||                                                                      ||"
echo "||                 >>> COPY/SAVE THE OUTPUT FROM HERE <<<               ||"
echo "||                                                                      ||"
echo "||  -> Solana cluster: ${cluster}                                       ||"
echo "||  -> queueKey: ${queueKey}                                            ||"
echo "||                                                                      ||"
echo "||  Creating new registration request for:                              ||"
if [[ "${register_oracle}" == "y" || "${register_oracle}" == "Y" ]]; then
  echo "||    -> ORACLE                                                         ||"
fi
if [[ "${register_guardian}" == "y" || "${register_guardian}" == "Y" ]]; then
  echo "||    -> GUARDIAN                                                       ||"
fi
echo "||                                                                      ||"
echo "=========================================================================="
echo " "

if [[ "${register_oracle}" == "y" || "${register_oracle}" == "Y" ]]; then
  echo " "
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
  echo " "
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

echo " "
echo "=========================================================================="
echo "||                       !!! IMPORTANT NOTICE !!!                       ||"
echo "=========================================================================="
echo "||                                                                      ||"
echo "|| The output above contains your Oracle/Guardian public keys and       ||"
echo "|| related data.                                                        ||"
echo "||                                                                      ||"
echo "|| It's safe to share your PUBKEYs for your Oracle and Guardian as the  ||"
echo "|| the name implies they are in fact public.                            ||"
echo "||                                                                      ||"
echo "|| PUBKEYs example:                                                     ||"
echo "||   PULL_ORACLE=AbCdEfGhIjKlMnOpQrStUvXwYz1234567890AbCdEfGh           ||"
echo "||   GUARDIAN_ORACLE=AbCdEfGhIjKlMnOpQrStUvXwYz1234567890AbCdEfGh       ||"
echo "||                                                                      ||"
echo "|| The QUEUE variables are fixed among all Oracles & Guardians as they  ||"
echo "|| represent the Solana queues we use to coordinate operations on chain ||"
echo "|| and only change between devnet vs mainnet.                           ||"
echo "||                                                                      ||"
echo "|| QUEUE devnet vars :                                                  ||"
echo "||   PULL_QUEUE=EYiAmGSdsQTuCw413V5BzaruWuCCSDgTPtBGvLkXHbe7            ||"
echo "||   GUARDIAN_QUEUE=BeZ4tU4HNe2fGQGUzJmNS2UU2TcZdMUUgnCH6RPg4Dpi        ||"
echo "|| QUEUE mainnet vars :                                                 ||"
echo "||   PULL_QUEUE=A43DyUGA7s8eXPxqEjJY6EBu1KKbNgfxF8h17VAHn13w            ||"
echo "||   GUARDIAN_QUEUE=B7WgdyAgzK7yGoxfsBaNnY6d41bTybTzEh4ZuQosnvLK        ||"
echo "||                                                                      ||"
echo "|| SECURITY WARNING:                                                    ||"
echo "||  Keep your 24-word seed phrase and private key (array-like number)   ||"
echo "||                         ABSOLUTELY PRIVATE!                          ||"
echo "||                                                                      ||"
echo "|| Next steps:                                                          ||"
echo "||   1. Edit cfg/00-devnet-vars.cfg or cfg/00-mainnet-vars.cfg file     ||"
echo "||      and insert the output in the proper variables                   ||"
echo "||                                                                      ||"
echo "||   2. Submit a request for approval of your Oracle/Guardian data at:  ||"
echo "||                                                                      ||"
echo "||      https://forms.gle/2xWwFQ8XPBGu9DRL6                             ||"
echo "||                                                                      ||"
echo "||      In the form you should just submit the values of                ||"
echo "||        PULL_ORACLE     + PULL_QUEUE                                  ||"
echo "||                                                                      ||"
echo "||      and only if you are runnning a guardian also send               ||"
echo "||        GUARDIAN_ORACLE + GUARDIAN_QUEUE                              ||"
echo "||                                                                      ||"
echo "||   3. Please save the output above and then you can exit now          ||"
echo "||      Wait for approval before proceeding with the following steps    ||"
echo "||                                                                      ||"
echo "||          SAVE THIS OUTPUT NOW, THEN TYPE 'exit' TO CONTINUE          ||"
echo "=========================================================================="
echo " "
