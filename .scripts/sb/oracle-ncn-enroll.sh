#!/usr/bin/env bash
set -u -e

export DEBUG="${DEBUG:-false}"
if [[ "${DEBUG}" == "true" ]]; then
  set -x
fi

cluster="${1:-devnet}"

if [[ "${cluster}" != "devnet" &&
  "${cluster}" != "mainnet" ]]; then
  printf "Only valid cluster values are 'devnet' (default) and 'mainnet'\n"
  exit 254
fi

export PAYER_FILE="/data/${cluster}_payer.json"
export NCN_PAYER_FILE="${PAYER_FILE}"

export CFG_FILE="/cfg/00-${cluster}-vars.cfg"

source <(awk '/^NETWORK=/' "${CFG_FILE}")
source <(awk '/^RPC_URL=/' "${CFG_FILE}")

# source ORACLE_OPERATOR from cfg file
source <(awk \
  '/^PULL_ORACLE=/ {gsub("PULL_ORACLE","ORACLE_OPERATOR", $0); print $0}' \
  "${CFG_FILE}")

export NCN=""
export VAULT=""

if [[ "${cluster}" == "devnet" ]]; then
  NCN=A9muHr9VqgabHCeEgXyGuAeeAVcW8nLJeHLsmWYGLbv5
  VAULT=BxhsigZDYjWTzXGgem9W3DsvJgFpEK5pM2RANP22bxBE
elif [[ "${cluster}" == "mainnet" ]]; then
  NCN=BGTtt2wdTdhLyFQwSGbNriLZiCxXKBbm29bDvYZ4jD6G
  VAULT=HR1ANmDHjaEhknvsTaK48M5xZtbBiwNdXM5NTiWhAb4S
fi

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

if [[ -z "${NCN_OPERATOR}" ]]; then

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
  printf "\n"

  export NCN_OPERATOR_FEE=100
  if [[ "${NCN_OPERATOR_EXISTING}" == "n" || "${NCN_OPERATOR_EXISTING}" == "N" ]]; then
    cmd="jito-restaking-cli restaking operator initialize ${NCN_OPERATOR_FEE} --rpc-url ${RPC_URL} --keypair ${PAYER_FILE}"
    printf "Creating an NCN OPERATOR account for you, please stand by.\n"
    NCN_OPERATOR="$(${cmd} 2>&1 | awk '/Operator initialized at address/ {print $NF}')"
  else
    printf "Please provide your current NCN operator: "
    read -r NCN_OPERATOR
  fi

  export SAVE_NCN_OPERATOR=""
  while [[ 
    "${SAVE_NCN_OPERATOR}" != "y" &&
    "${SAVE_NCN_OPERATOR}" != "Y" &&
    "${SAVE_NCN_OPERATOR}" != "n" &&
    "${SAVE_NCN_OPERATOR}" != "N" ]]; do
    printf "Do you want me to write this NCN operator in ${CFG_FILE} for you? (y/n) "
    read -r SAVE_NCN_OPERATOR
  done

  if [[ "${SAVE_NCN_OPERATOR}" == "y" || "${SAVE_NCN_OPERATOR}" == "Y" ]]; then
    sed -i "s/^NCN_OPERATOR=.*/NCN_OPERATOR=${NCN_OPERATOR}/" "${CFG_FILE}"
  fi
else
  printf "Imported NCN_OPERATOR from ${CFG_FILE}\n"
  printf "Please reset the NCN_OPERATOR variable in that file if this was not intended\n"
fi
printf "\n"

printf "\n"
printf "==========================================================================\n"
printf "||                       !!! IMPORTANT NOTICE !!!                       ||\n"
printf "==========================================================================\n"
printf "||                                                                      ||\n"
printf "||             >>> COPY/SAVE THIS OUTPUT TO A SAFE PLACE <<<            ||\n"
printf "||                                                                      ||\n"
printf "|| Creating new Oracle/Guardian permission request on Solana for:       ||\n"
printf "%-6s%16s %-44s%7s\n" "||" "Solana cluster:" "${cluster}" " ||"
printf "%-6s%16s %-44s%7s\n" "||" "NCN:" "${NCN}" " ||"
printf "%-6s%16s %-44s%7s\n" "||" "VAULT:" "${VAULT}" " ||"
printf "%-6s%16s %-44s%7s\n" "||" "NCN_OPERATOR:" "${NCN_OPERATOR}" " ||"
printf "||                                                                      ||\n"
printf "==========================================================================\n"
printf "\n"

export NCN_OPERATOR_ADMIN="$(jito-restaking-cli restaking operator get ${NCN_OPERATOR} --rpc-url ${RPC_URL} 2>&1 | sed 's/.* admin: \(.\{44\}\).*/\1/g')"
export ORACLE_OPERATOR_AUTHORITY="$(sb solana on-demand oracle print --cluster ${cluster} --rpcUrl ${RPC_URL} ${ORACLE_OPERATOR} 2>&1 | awk '/authority/ {print $(NF)}"

if [[ "${NCN_OPERATOR_ADMIN}" == "${ORACLE_OPERATOR_AUTHORITY}" ]]; then
  jito-restaking-cli restaking operator initialize-operator-vault-ticket ${ORACLE_OPERATOR} ${VAULT} --rpc-url ${RPC_URL} --keypair ${NCN_PAYER_FILE}
  jito-restaking-cli restaking operator warmup-operator-vault-ticket ${ORACLE_OPERATOR} ${VAULT} --rpc-url ${RPC_URL} --keypair ${NCN_PAYER_FILE}
  sb solana on-demand oracle setOperator ${ORACLE_OPERATOR} --operator ${NCN_OPERATOR} --cluster ${cluster} -u ${RPC_URL} -k ${PAYER_FILE}
else
  printf "\n"
  printf "jito-restaking-cli restaking operator initialize-operator-vault-ticket ${ORACLE_OPERATOR} ${VAULT} --rpc-url ${RPC_URL} --keypair ${NCN_PAYER_FILE}\n"
  printf "jito-restaking-cli restaking operator warmup-operator-vault-ticket ${ORACLE_OPERATOR} ${VAULT} --rpc-url ${RPC_URL} --keypair ${NCN_PAYER_FILE}\n"
  printf "sb solana on-demand oracle setOperator ${ORACLE_OPERATOR} --operator ${NCN_OPERATOR} --cluster ${cluster} -u ${RPC_URL} -k ${PAYER_FILE}\n"
  printf "\n"
fi

printf "\n"
printf "Please notify SWITCHBOARD that you registered you oracle to the NCN vault.\n"
printf "They'll need to validate and confirm on their side, then you should come back and run the following step\n"

printf "\n"
printf "After SWITCHBOARD confims they have run their part of process,\n"
printf "please come back to this temporary container using ./50-... and then run:\n"
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
