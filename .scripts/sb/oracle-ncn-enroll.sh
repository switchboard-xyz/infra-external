#!/usr/bin/env bash
set -u -e

function debug() {
  if [[ "${DEBUG}" == "true" ]]; then
    printf "DEBUG: $@\n"
  fi
}

cluster="${1:-devnet}"

if [[ "${cluster}" != "devnet" &&
  "${cluster}" != "mainnet" ]]; then
  printf "Only valid cluster values are 'devnet' (default) and 'mainnet'\n"
  exit 254
fi

export DEBUG="${DEBUG:-false}"
debug "DEBUG=${DEBUG}"

export PAYER_FILE="/data/${cluster}_payer.json"
debug "PAYER_FILE=${PAYER_FILE}"
export NCN_PAYER_FILE="${PAYER_FILE}"
debug "NCN_PAYER_FILE=${NCN_PAYER_FILE}"

export CFG_FILE="/cfg/00-${cluster}-vars.cfg"
debug "CFG_FILE=${CFG_FILE}"

source <(awk '/^NETWORK=/' "${CFG_FILE}")
debug "NETWORK=${NETWORK}"
source <(awk '/^RPC_URL=/' "${CFG_FILE}")
debug "RPC_URL=${RPC_URL}"

# source ORACLE_OPERATOR from cfg file
source <(awk \
  '/^PULL_ORACLE=/ {gsub("PULL_ORACLE","ORACLE_OPERATOR", $0); print $0}' \
  "${CFG_FILE}")
debug "ORACLE_OPERATOR=${ORACLE_OPERATOR}"

export NCN=""
export VAULT=""

if [[ "${cluster}" == "devnet" ]]; then
  NCN=A9muHr9VqgabHCeEgXyGuAeeAVcW8nLJeHLsmWYGLbv5
  VAULT=BxhsigZDYjWTzXGgem9W3DsvJgFpEK5pM2RANP22bxBE
elif [[ "${cluster}" == "mainnet" ]]; then
  NCN=BGTtt2wdTdhLyFQwSGbNriLZiCxXKBbm29bDvYZ4jD6G
  VAULT=HR1ANmDHjaEhknvsTaK48M5xZtbBiwNdXM5NTiWhAb4S
fi
debug "NCN=${NCN}"
debug "VAULT=${VAULT}"

export NCN_OPERATOR=""
source <(awk '/^NCN_OPERATOR=/' "${CFG_FILE}")

printf "\n"
printf "==========================================================================\n"
printf "||                                                                      ||\n"
printf "||                 YOU ARE NOW IN A TEMPORARY CONTAINER                 ||\n"
printf "||          PLEASE FOLLOW THE INSTRUCTIONS BELOW AND THE DOCS           ||\n"
printf "||                                                                      ||\n"
printf "==========================================================================\n"
printf "\n"

export NCN_OPERATOR_EXISTING=""

if [[ -z "${NCN_OPERATOR}" ]]; then
  printf "\n"
  while [[ 
    "${NCN_OPERATOR_EXISTING}" != "y" &&
    "${NCN_OPERATOR_EXISTING}" != "Y" &&
    "${NCN_OPERATOR_EXISTING}" != "n" &&
    "${NCN_OPERATOR_EXISTING}" != "N" ]]; do
    printf "Do you already have a NCN operator? (y/n) "
    read -r NCN_OPERATOR_EXISTING
  done
  printf "\n"
  debug "NCN_OPERATOR_EXISTING=${NCN_OPERATOR_EXISTING}"

  export NCN_OPERATOR_FEE=100

  if [[ "${NCN_OPERATOR_EXISTING}" == "n" || "${NCN_OPERATOR_EXISTING}" == "N" ]]; then
    cmd="jito-restaking-cli restaking operator initialize ${NCN_OPERATOR_FEE} --rpc-url ${RPC_URL} --keypair ${PAYER_FILE}"
    printf "Creating an NCN OPERATOR account for you:\n%s\n" "${cmd}"
    NCN_OPERATOR="$(${cmd} 2>&1 | awk '/Operator initialized at address/ {print $NF}')"
  else
    printf "Please provide your current NCN operator: "
    read -r NCN_OPERATOR
    while [[ 
      "${SAVE_NCN_OPERATOR}" != "y" &&
      "${SAVE_NCN_OPERATOR}" != "Y" &&
      "${SAVE_NCN_OPERATOR}" != "n" &&
      "${SAVE_NCN_OPERATOR}" != "N" ]]; do
      printf "Do you want to save this NCN operator in ${CFG_FILE}? (y/n) "
      read -r SAVE_NCN_OPERATOR
    done

    if [[ "SAVE_NCN_OPERATOR" == "y" || "SAVE_NCN_OPERATOR" == "Y" ]]; then
      sed -i "s/^NCN_OPREATOR=.*/NCN_OPERATOR=${NCN_OPERATOR}/" "${CFG_FILE}"
    fi
  fi
fi
debug "NCN_OPERATOR=${NCN_OPERATOR}"
printf "Your NCN OPERATOR is: %s\n" "${NCN_OPERATOR}"

printf "\n"
printf "jito-restaking-cli restaking operator initialize-operator-vault-ticket ${ORACLE_OPERATOR} ${VAULT} --rpc-url ${RPC_URL} --keypair ${NCN_PAYER_FILE}\n"
printf "jito-restaking-cli restaking operator warmup-operator-vault-ticket ${ORACLE_OPERATOR} ${VAULT} --rpc-url ${RPC_URL} --keypair ${NCN_PAYER_FILE}\n"
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
