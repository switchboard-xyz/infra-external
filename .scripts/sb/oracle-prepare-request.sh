cluster="${1:-devnet}"
priorityFee="${2:-10000}"

PAYER_FILE="/data/${cluster}_payer.json"
DEBUG="${DEBUG:-false}"

if [[ "${cluster}" != "devnet" &&
  "${cluster}" != "mainnet" &&
  "${cluster}" != "mainnet-beta" ]]; then
  echo "Only valid cluster values are 'devnet' and 'mainnet'/'mainnet-beta'"
  exit 1
fi

if [[ "${cluster}" == "mainnet" ]]; then
  cluster="mainnet-beta"
fi

queueKey=""
if [[ "${cluster}" == "devnet" ]]; then
  queueKey="EYiAmGSdsQTuCw413V5BzaruWuCCSDgTPtBGvLkXHbe7"
elif [[ "${cluster}" == "mainnet-beta" ]]; then
  queueKey="A43DyUGA7s8eXPxqEjJY6EBu1KKbNgfxF8h17VAHn13w"
fi

echo "==================================================="
echo "=                !!! IMPORTANT !!!                ="
echo "=  YOU ARE NOW IN A TEMPORARY CONTAINER. PLEASE   ="
echo "=  FOLLOW THE INSTRUCTIONS BELOW AND THE DOCS.    ="
echo "==================================================="
echo " "

if [[ "${cluster}" != "devnet" &&
  "${cluster}" != "mainnet" &&
  "${cluster}" != "mainnet-beta" ]]; then
  echo "Only valid cluster values are 'devnet' and 'mainnet'/'mainnet-beta'"
  exit 1
fi

if [[ "$(type -p sb)" == "" ]]; then
  echo " "
  echo "Installing Switchboard CLI now... please wait."
  echo "This step usually takes about 2 minutes."
  npm i -g "@switchboard-xyz/cli@3.5.8" >/dev/null 2>&1
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

echo "==================================================="
echo "=                !!! IMPORTANT !!!                ="
echo "=         COPY/SAVE THE OUTPUT FROM HERE          ="
echo "==================================================="
echo " "
echo "Creating new Oracle/Guardian permission request on Solana for:"
echo "  -> Solana cluster: ${cluster}"
echo "  -> queueKey: ${queueKey}"

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
echo "||                         !!! IMPORTANT NOTICE !!!                     ||"
echo "=========================================================================="
echo "||                                                                      ||"
echo "|| The output above contains your Oracle/Guardian public keys and       ||"
echo "|| related data.                                                        ||"
echo "||                                                                      ||"
echo "|| SECURITY WARNING:                                                    ||"
echo "||  Keep your 24-word seed phrase and private key (array-like number)   ||"
echo "||                  ABSOLUTELY PRIVATE!                                 ||"
echo "||                                                                      ||"
echo "|| Next steps:                                                          ||"
echo "||   1. Edit infra-external/cfg/00-vars.cfg and insert the output       ||"
echo "||      in the proper variables                                         ||"
echo "||                                                                      ||"
echo "||   2. Submit a request for approval of your Oracle/Guardian data at:  ||"
echo "||      https://forms.gle/2xWwFQ8XPBGu9DRL6                             ||"
echo "||                                                                      ||"
echo "||   3. Wait for approval before proceeding with further steps          ||"
echo "||                                                                      ||"
echo "||   4. If you want to come back and use step 52, you'll have to rerun  ||"
echo "||      step 50 to reenter this temporary container.                    ||"
echo "||                                                                      ||"
echo "||          SAVE THIS OUTPUT NOW, THEN TYPE 'exit' TO CONTINUE          ||"
echo "=========================================================================="
echo " "
