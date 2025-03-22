#!/usr/bin/env bash

cluster="${1:-devnet}"

if [[ "${cluster}" != "devnet" &&
  "${cluster}" != "mainnet" ]]; then
  echo "Only valid cluster values are 'devnet' and 'mainnet'"
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

# TODO:
export RPC_URL="DEVNET_OR_MAINNET_RPC"
export OPERATOR_ORACLE="DEVNET_OR_MAINNET_ORACLE_PUBKEY"
export OPERATOR_NCN="DEVNET_OR_MAINNET_NCN_PUBKEY"
# END:

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
export OPERATOR_NCN_EXISTING=""
while [[ 
  "${OPERATOR_NCN_EXISTING}" != "y" &&
  "${OPERATOR_NCN_EXISTING}" != "Y" &&
  "${OPERATOR_NCN_EXISTING}" != "n" &&
  "${OPERATOR_NCN_EXISTING}" != "N" ]]; do
  echo -n "Do you already have a NCN operator? (y/n) "
  read -r OPERATOR_NCN_EXISTING
done

if [[ "${OPERATOR_NCN_EXISTING}" == "N" || "${OPERATOR_NCN_EXISTING}" == "N" ]]; then
  # TODO:
  jito-restaking-cli restaking operator initialize 100 --rpc-url ${RPC_URL} --keypair ${PAYER_FILE}
  # END
else
  echo -n "Please provide your current NCN operator: "
  read -r OPERATOR_NCN
fi

# TODO:
jito-restaking-cli restaking operator initialize-operator-vault-ticket ${OPERATOR_ORACLE} ${VAULT} --rpc-url ${RPC_URL} --keypair ${PAYER_FILE}
jito-restaking-cli restaking operator warmup-operator-vault-ticket ${OPERATOR_ORACLE} ${VAULT} --rpc-url ${RPC_URL} --keypair ${PAYER_FILE}
sb solana on-demand oracle setOperator ${OPERATOR_ORACLE} --operator ${OPERATOR_NCN} -u ${RPC_URL} -k ${PAYER_FILE}
# END

echo " "
echo "=========================================================================="
echo "||                       !!! IMPORTANT NOTICE !!!                       ||"
echo "=========================================================================="
echo "||                                                                      ||"
echo "||                 >>> COPY/SAVE THE OUTPUT FROM HERE <<<               ||"
echo "||                                                                      ||"
echo "|| Creating new Oracle/Guardian permission request on Solana for:       ||"
echo "||  -> Solana cluster: ${cluster}                                       ||"
echo "||  -> NCN: ${NCN}                                                      ||"
echo "||  -> VAULT: ${VAULT}                                                  ||"
echo "||                                                                      ||"
echo "=========================================================================="
echo " "

# TODO:
# 5 ... THEN WE RUN ...
jito-restaking-cli restaking ncn initialize-ncn-operator-state ${NCN} ${OPERATOR_NCN} --rpc-url ${RPC_URL} --keypair ${NCN_ADMIN_AUTH_PAYER_FILE}

# 6 ... THEN OPERATORS RUN...
jito-restaking-cli restaking operator operator-warmup-ncn ${OPERATOR_NCN} ${NCN} --rpc-url ${RPC_URL} --keypair ${PAYER_FILE}

# 7 ... THEN FRAGMETRICS RUN ...
jito-restaking-cli vault vault initialize-operator-delegation
# END

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
