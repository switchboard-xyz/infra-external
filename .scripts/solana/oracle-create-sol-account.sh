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

PAYER_FILE="/data/${cluster}_payer.json"

printf "\n"
printf "==========================================================================\n"
printf "||                                                                      ||\n"
printf "||                 YOU ARE NOW IN A TEMPORARY CONTAINER                 ||\n"
printf "||          PLEASE FOLLOW THE INSTRUCTIONS BELOW AND THE DOCS           ||\n"
printf "||                                                                      ||\n"
printf "==========================================================================\n"
printf "\n"

printf "\n"
printf "Installing deps.. usually about 1-2 minutes.\n"
apt-get update >/dev/null 2>&1 &&
  apt-get install -y ca-certificates >/dev/null 2>&1

solana-keygen new --force --word-count 24 -o "${PAYER_FILE}"

cat "${PAYER_FILE}"

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
  solana airdrop 5 -u "${cluster}" -k "${PAYER_FILE}"
fi

printf "\n"
printf "Checking current balance for your new account:\n"
solana balance -u "${cluster}" -k "${PAYER_FILE}"

printf "\n"
printf "==========================================================================\n"
printf "||                       !!! IMPORTANT NOTICE !!!                       ||\n"
printf "==========================================================================\n"
printf "||                                                                      ||\n"
printf "||             COPY/SAVE THE OUTPUT ABOVE, BEFORE PROCEEDING            ||\n"
printf "||          SAVE THIS OUTPUT NOW, THEN TYPE 'exit' TO CONTINUE          ||\n"
printf "||                                                                      ||\n"
printf "==========================================================================\n"
printf "\n"
