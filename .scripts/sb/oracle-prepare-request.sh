#!/usr/bin/env bash
set -u -e

cluster="${1:-devnet}"
priorityFee="${2:-10000}"

set +u
if [[ -z "${1}" ]]; then
  printf "No cluster specified, using default: 'devnet'\n"
fi
set -u

if [[ "${cluster}" != "devnet" &&
  "${cluster}" != "mainnet" ]]; then
  printf "Only valid cluster values are 'devnet' and 'mainnet'\n"
  exit 1
fi

set +u
if [[ -z "${2}" ]]; then
  printf "No priorityFee specified, using default: '${priorityFee}'\n"
fi
set -u

export DEBUG="${DEBUG:-false}"
if [[ "${DEBUG}" == "true" ]]; then
  set -x
fi

export PAYER_FILE="/data/${cluster}_payer.json"
export CFG_FILE="/cfg/00-${cluster}-vars.cfg"

# Load existing configuration if available
if [[ -f "${CFG_FILE}" ]]; then
  source <(awk '/^PULL_ORACLE=/' "${CFG_FILE}")
  source <(awk '/^GUARDIAN_ORACLE=/' "${CFG_FILE}")
  source <(awk '/^RPC_URL=/' "${CFG_FILE}")
fi

# Set queue keys based on cluster
export PULL_QUEUE_KEY=""
export GUARDIAN_QUEUE_KEY=""
if [[ "${cluster}" == "devnet" ]]; then
  PULL_QUEUE_KEY="EYiAmGSdsQTuCw413V5BzaruWuCCSDgTPtBGvLkXHbe7"
  GUARDIAN_QUEUE_KEY="BeZ4tU4HNe2fGQGUzJmNS2UU2TcZdMUUgnCH6RPg4Dpi"
elif [[ "${cluster}" == "mainnet" ]]; then
  PULL_QUEUE_KEY="A43DyUGA7s8eXPxqEjJY6EBu1KKbNgfxF8h17VAHn13w"
  GUARDIAN_QUEUE_KEY="B7WgdyAgzK7yGoxfsBaNnY6d41bTybTzEh4ZuQosnvLK"
fi

printf "\n"
printf "==========================================================================\n"
printf "||                                                                      ||\n"
printf "||                 YOU ARE NOW IN A TEMPORARY CONTAINER                 ||\n"
printf "||          PLEASE FOLLOW THE INSTRUCTIONS BELOW AND THE DOCS           ||\n"
printf "||                                                                      ||\n"
printf "==========================================================================\n"
printf "\n"

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
printf "||  -> Pull Queue: %44s %10s\n" "${PULL_QUEUE_KEY}" "||"
if [[ "${register_guardian}" == "y" || "${register_guardian}" == "Y" ]]; then
  printf "||  -> Guardian Queue: %44s %6s\n" "${GUARDIAN_QUEUE_KEY}" "||"
fi
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

# Variables to store the created keys
export PULL_ORACLE_KEY=""
export GUARDIAN_ORACLE_KEY=""

export SAVE_ORACLE_KEY=""
export SAVE_GUARDIAN_KEY=""
if [[ "${register_oracle}" == "y" || "${register_oracle}" == "Y" ]]; then
  printf "\n"
  export ORACLE_OUTPUT=""
  if [[ "${DEBUG}" == "true" ]]; then
    ORACLE_OUTPUT=$(
      sb solana on-demand oracle create \
        --queue "${PULL_QUEUE_KEY}" \
        --cluster "${cluster}" \
        --priorityFee "${priorityFee}" \
        --rpcUrl "${RPC_URL}" \
        --keypair "${PAYER_FILE}"
    )
    printf "%s\n" "${ORACLE_OUTPUT}"
  else
    ORACLE_OUTPUT=$(
      sb solana on-demand oracle create \
        --queue "${PULL_QUEUE_KEY}" \
        --cluster "${cluster}" \
        --priorityFee "${priorityFee}" \
        --rpcUrl "${RPC_URL}" \
        --keypair "${PAYER_FILE}" 2>/dev/null
    )
    printf "%s\n" "${ORACLE_OUTPUT}"
  fi
  PULL_ORACLE_KEY=$(echo "${ORACLE_OUTPUT}" | awk -F '=' '/^PULL_ORACLE=/ {print $NF}')

  # Save the oracle key to config file if it was created successfully
  if [[ -n "${PULL_ORACLE_KEY}" ]]; then
    printf "\n"
    printf "Oracle key created: %s\n" "${PULL_ORACLE_KEY}"

    export SAVE_ORACLE_KEY=""
    while [[ 
      "${SAVE_ORACLE_KEY}" != "y" &&
      "${SAVE_ORACLE_KEY}" != "Y" &&
      "${SAVE_ORACLE_KEY}" != "n" &&
      "${SAVE_ORACLE_KEY}" != "N" ]]; do
      printf "Do you want to save this Oracle key to ${CFG_FILE}? (y/n) "
      read -r SAVE_ORACLE_KEY
    done

    if [[ "${SAVE_ORACLE_KEY}" == "y" || "${SAVE_ORACLE_KEY}" == "Y" ]]; then
      sed -i "s/^PULL_ORACLE=.*/PULL_ORACLE=${PULL_ORACLE_KEY}/" "${CFG_FILE}"
      sed -i "s/^PULL_QUEUE=.*/PULL_QUEUE=${PULL_QUEUE_KEY}/" "${CFG_FILE}"
      printf "Oracle key saved to config file.\n"
    fi
  fi
fi

if [[ "${register_guardian}" == "y" || "${register_guardian}" == "Y" ]]; then
  printf "\n"
  export GUARDIAN_OUTPUT=""
  if [[ "${DEBUG}" == "true" ]]; then
    GUARDIAN_OUTPUT=$(
      sb solana on-demand guardian create \
        --cluster "${cluster}" \
        --priorityFee "${priorityFee}" \
        --keypair "${PAYER_FILE}"
    )
    printf "%s\n" "${GUARDIAN_OUTPUT}"
  else
    GUARDIAN_OUTPUT=$(
      sb solana on-demand guardian create \
        --cluster "${cluster}" \
        --priorityFee "${priorityFee}" \
        --keypair "${PAYER_FILE}" 2>/dev/null
    )
    printf "%s\n" "${GUARDIAN_OUTPUT}"
  fi
  GUARDIAN_ORACLE_KEY=$(echo "${GUARDIAN_OUTPUT}" | awk -F '=' '/^GUARDIAN_ORACLE=/ {print $NF}')

  # Save the guardian key to config file if it was created successfully
  if [[ -n "${GUARDIAN_ORACLE_KEY}" ]]; then
    printf "\n"
    printf "Guardian key created: %s\n" "${GUARDIAN_ORACLE_KEY}"

    export SAVE_GUARDIAN_KEY=""
    while [[ 
      "${SAVE_GUARDIAN_KEY}" != "y" &&
      "${SAVE_GUARDIAN_KEY}" != "Y" &&
      "${SAVE_GUARDIAN_KEY}" != "n" &&
      "${SAVE_GUARDIAN_KEY}" != "N" ]]; do
      printf "Do you want to save this Guardian key to ${CFG_FILE}? (y/n) "
      read -r SAVE_GUARDIAN_KEY
    done

    if [[ "${SAVE_GUARDIAN_KEY}" == "y" || "${SAVE_GUARDIAN_KEY}" == "Y" ]]; then
      sed -i "s/^GUARDIAN_ORACLE=.*/GUARDIAN_ORACLE=${GUARDIAN_ORACLE_KEY}/" "${CFG_FILE}"
      sed -i "s/^GUARDIAN_QUEUE=.*/GUARDIAN_QUEUE=${GUARDIAN_QUEUE_KEY}/" "${CFG_FILE}"
      printf "Guardian key saved to config file.\n"
    fi
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
if [[ "${SAVE_ORACLE_KEY}" == "y" || "${SAVE_ORACLE_KEY}" == "Y" ]] &&
  [[ "${SAVE_GUARDIAN_KEY}" == "y" || "${SAVE_GUARDIAN_KEY}" == "Y" ]]; then
  printf "||   1. Your Oracle & Guardian keys have been automatically saved to:   ||\n"
  printf "||                                                                      ||\n"
  printf "%-10s%-61s%3s\n" "|| " "${CFG_FILE}" " ||"
elif [[ "${SAVE_ORACLE_KEY}" == "y" || "${SAVE_ORACLE_KEY}" == "Y" ]] &&
  [[ "${register_guardian}" == "y" || "${register_guardian}" == "Y" ]]; then
  printf "||   1. Your Oracle key has been automatically saved to                 ||\n"
  printf "||                                                                      ||\n"
  printf "%-10s%-61s%3s\n" "|| " "${CFG_FILE}" " ||"
  printf "||      but you'll need to manually add your Guardian key               ||\n"
elif [[ "${SAVE_GUARDIAN_KEY}" == "y" || "${SAVE_GUARDIAN_KEY}" == "Y" ]] &&
  [[ "${register_oracle}" == "y" || "${register_oracle}" == "Y" ]]; then
  printf "||   1. Your Guardian key has been automatically saved to               ||\n"
  printf "||                                                                      ||\n"
  printf "%-10s%-61s%3s\n" "|| " "${CFG_FILE}" " ||"
  printf "||      but you'll need to manually add your Oracle key                 ||\n"
elif [[ "${SAVE_ORACLE_KEY}" == "y" || "${SAVE_ORACLE_KEY}" == "Y" ]]; then
  printf "||   1. Your Oracle key has been automatically saved to                 ||\n"
  printf "||                                                                      ||\n"
  printf "%-10s%-61s%3s\n" "|| " "${CFG_FILE}" " ||"
elif [[ "${SAVE_GUARDIAN_KEY}" == "y" || "${SAVE_GUARDIAN_KEY}" == "Y" ]]; then
  printf "||   1. Your Guardian key has been automatically saved to               ||\n"
  printf "||                                                                      ||\n"
  printf "%-10s%-61s%3s\n" "|| " "${CFG_FILE}" " ||"
else
  printf "%-5s%-8s%-58s%3s\n" "|| " "1. Edit " "${CFG_FILE} file" " ||"
  printf "||      and add the values copied from above in the proper variables.   ||\n"
fi
printf "||                                                                      ||\n"
printf "||   2. Submit a request for approval of your Oracle/Guardian data at:  ||\n"
printf "||                                                                      ||\n"
printf "||        https://forms.gle/2xWwFQ8XPBGu9DRL6                           ||\n"
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
