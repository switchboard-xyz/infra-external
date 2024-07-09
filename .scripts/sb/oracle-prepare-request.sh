cluster="${1:-devnet}"
price="${2:-10000}"

PAYER_FILE="/data/${cluster}_payer.json"

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
  queueKey="FfD96yeXs4cxZshoPPSKhSPgVQxLAJUT3gefgh84m1Di"
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
  npm i -g "@switchboard-xyz/cli@3.5.3" >/dev/null 2>&1
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

if [[ "${register_guardian}" == "y" || "${register_guardian}" == "Y" ]]; then
  echo " "
  sb solana on-demand oracle create \
    --queue "${queueKey}" \
    --cluster "${cluster}" \
    --price "${price}" \
    --keypair "${PAYER_FILE}"
fi

if [[ "${register_guardian}" == "y" || "${register_guardian}" == "Y" ]]; then
  echo " "
  sb solana on-demand guardian create \
    --cluster "${cluster}" \
    --price "${price}" \
    --keypair "${PAYER_FILE}"
fi

echo " "
echo "==================================================="
echo "=                !!! IMPORTANT !!!                ="
echo "=  COPY/SAVE THE OUTPUT ABOVE, BEFORE PROCEEDING  ="
echo "=  THEN TYPE 'exit' TO LEAVE THIS TMP CONTAINER.  ="
echo "==================================================="
echo " "
