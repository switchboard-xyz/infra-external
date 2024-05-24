cluster="${1:-devnet}"
queueKey="${2:-FfD96yeXs4cxZshoPPSKhSPgVQxLAJUT3gefgh84m1Di}"

echo "Creating new Oracle/Guardian permission request on Solana for:"
echo "  -> Solana cluster: ${cluster}"
echo "  -> queueKey: ${queueKey}"

echo " "
echo "Installing Switchboard CLI now... please wait."
echo "This step usually takes about 2 minutes."
npm i -g "@switchboard-xyz/cli@3.3.40" >/dev/null 2>&1

echo " "
sb solana on-demand oracle create \
	--queue "${queueKey}" \
	--cluster "${cluster}" \
	--keypair payer.json

echo " "
export register_guardian=""
while [[ 
	"${register_guardian}" != "y" &&
	"${register_guardian}" != "Y" &&
	"${register_guardian}" != "n" &&
	"${register_guardian}" != "n" ]]; do
	echo -n "Do you plan on running a guardian as well? (y/n) "
	read -r register_guardian
done

if [[ "${register_guardian}" == "y" || "${register_guardian}" == "Y" ]]; then
	echo " "
	sb solana on-demand guardian create \
		--cluster "${cluster}" \
		--keypair payer.json
fi

echo " "
echo "!!! IMPORTANT !!!"
echo "SAVE THE OUTPUT from the commands above before proceeding."

echo " "
echo "Should be safe to exit now. Just type 'exit' from this temporary container."
