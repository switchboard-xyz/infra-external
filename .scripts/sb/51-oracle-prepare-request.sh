cluster="${1:-devnet}"
queueKey="${2:-FfD96yeXs4cxZshoPPSKhSPgVQxLAJUT3gefgh84m1Di}"

PAYER_FILE="/data/${cluster}_payer.json"

if [[ "${cluster}" == "mainnet" ]]; then
	cluster="mainnet-beta"
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
	echo "Only valid cluster values are 'devnet' and 'mainnet'/'mainnet-beta'."
	exit 1
fi

echo " "
echo "Installing Switchboard CLI now... please wait."
echo "This step usually takes about 2 minutes."
npm i -g "@switchboard-xyz/cli@3.3.44" >/dev/null 2>&1

echo " "
export register_guardian=""
while [[ 
	"${register_guardian}" != "y" &&
	"${register_guardian}" != "Y" &&
	"${register_guardian}" != "n" &&
	"${register_guardian}" != "N" ]]; do
	echo -n "Do you plan on running a guardian as well? (y/n) "
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

echo " "
sb solana on-demand oracle create \
	--queue "${queueKey}" \
	--cluster "${cluster}" \
	--keypair "${PAYER_FILE}"

if [[ "${register_guardian}" == "y" || "${register_guardian}" == "Y" ]]; then
	echo " "
	sb solana on-demand guardian create \
		--cluster "${cluster}" \
		--keypair "${PAYER_FILE}"
fi

echo " "
echo "==================================================="
echo "=                !!! IMPORTANT !!!                ="
echo "=  COPY/SAVE THE OUTPUT ABOVE, BEFORE PROCEEDING  ="
echo "=  THEN TYPE 'exit' TO LEAVE THIS TMP CONTAINER.  ="
echo "==================================================="
echo " "
