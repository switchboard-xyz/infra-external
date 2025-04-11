#!/usr/bin/env bash
set -u -e

cluster="${1:-devnet}"

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

export DEBUG="${DEBUG:-false}"
if [[ "${DEBUG}" == "true" ]]; then
  set -x
fi

export PAYER_FILE="/data/${cluster}_payer.json"
export CFG_FILE="/cfg/00-${cluster}-vars.cfg"

# Load existing configuration if available
if [[ -f "${CFG_FILE}" ]]; then
  source <(awk '/^NETWORK=/' "${CFG_FILE}")
  source <(awk '/^RPC_URL=/' "${CFG_FILE}")
fi

printf "\n"
printf "==========================================================================\n"
printf "||                                                                      ||\n"
printf "||                 YOU ARE NOW IN A TEMPORARY CONTAINER                 ||\n"
printf "||          PLEASE FOLLOW THE INSTRUCTIONS BELOW AND THE DOCS           ||\n"
printf "||                                                                      ||\n"
printf "==========================================================================\n"
printf "\n"

# Check if payer file already exists
if [[ ! -z "$(cat ${PAYER_FILE})" ]]; then
  printf "\n"
  printf "========================================================================\n"
  printf "||                       !!! WARNING !!!                              ||\n"
  printf "========================================================================\n"
  printf "||                                                                    ||\n"
  printf "|| Our script detected that the payer file at location                 ||\n"
  printf "%-7s%-62s%3s\n" "||" "${PAYER_FILE}" "||"
  printf "|| already contains some data.                                        ||\n"
  printf "|| Continuing will OVERWRITE this file and you will LOSE ACCESS       ||\n"
  printf "|| to any funds associated with this account!                         ||\n"
  printf "||                                                                    ||\n"
  printf "|| THIS IS A DESTRUCTIVE OPERATION THAT CANNOT BE UNDONE!             ||\n"
  printf "||                                                                    ||\n"
  printf "========================================================================\n"
  printf "\n"

  export CONTINUE_OVERWRITE=""
  while [[ 
    "${CONTINUE_OVERWRITE}" != "y" &&
    "${CONTINUE_OVERWRITE}" != "Y" &&
    "${CONTINUE_OVERWRITE}" != "n" &&
    "${CONTINUE_OVERWRITE}" != "N" ]]; do
    printf "Do you want to continue and overwrite the existing payer file? (y/n) "
    read -r CONTINUE_OVERWRITE
  done

  if [[ "${CONTINUE_OVERWRITE}" == "n" || "${CONTINUE_OVERWRITE}" == "N" ]]; then
    printf "Operation cancelled. Exiting without creating a new account.\n"
    exit 0
  fi

  printf "Proceeding with overwrite as requested...\n\n"
fi

solana-keygen new --force --word-count 24 -o "${PAYER_FILE}"

# Display the generated key
PAYER_OUTPUT=$(cat "${PAYER_FILE}")
printf "%s\n" "${PAYER_OUTPUT}"

printf "\n"
printf "==========================================================================\n"
printf "||                       !!! IMPORTANT NOTICE !!!                       ||\n"
printf "==========================================================================\n"
printf "||                                                                      ||\n"
printf "|| SAVE THE 24 WORDS AND SEQUENCE OF NUMBERS ABOVE                      ||\n"
printf "|| OR YOU MAY LOSE ALL YOUR FUNDS IN FUTURE!!!                          ||\n"
printf "|| THESE ARE YOUR PRIVATE KEY, KEEP IT SECRET!!!                        ||\n"
printf "||                                                                      ||\n"
printf "==========================================================================\n"
printf "\n"

# only on devnet
if [[ "${cluster}" == "devnet" ]]; then
  printf "\n"
  printf "Requesting self-funding of 5 SOL on devnet:\n"
  if [[ "${DEBUG}" == "true" ]]; then
    AIRDROP_OUTPUT=$(solana airdrop 5 -u "${cluster}" -k "${PAYER_FILE}")
    printf "%s\n" "${AIRDROP_OUTPUT}"
  else
    AIRDROP_OUTPUT=$(solana airdrop 5 -u "${cluster}" -k "${PAYER_FILE}" 2>/dev/null)
    printf "%s\n" "${AIRDROP_OUTPUT}"
  fi
fi

printf "\n"
printf "Checking current balance for your new account:\n"
if [[ "${DEBUG}" == "true" ]]; then
  BALANCE_OUTPUT=$(solana balance -u "${cluster}" -k "${PAYER_FILE}")
  printf "%s\n" "${BALANCE_OUTPUT}"
else
  BALANCE_OUTPUT=$(solana balance -u "${cluster}" -k "${PAYER_FILE}" 2>/dev/null)
  printf "%s\n" "${BALANCE_OUTPUT}"
fi

printf "\n"
printf "==========================================================================\n"
printf "||                       !!! IMPORTANT NOTICE !!!                       ||\n"
printf "==========================================================================\n"
printf "||                                                                      ||\n"
printf "||             COPY/SAVE THE OUTPUT ABOVE, BEFORE PROCEEDING            ||\n"
printf "||                                                                      ||\n"
printf "||          SAVE THIS OUTPUT NOW, THEN TYPE 'exit' TO CONTINUE          ||\n"
printf "||                                                                      ||\n"
printf "==========================================================================\n"
printf "\n"
