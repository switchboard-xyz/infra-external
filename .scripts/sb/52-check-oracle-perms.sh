cluster="${1:-devnet}"

if [[ "${cluster}" != "devnet" &&
	"${cluster}" != "mainnet" &&
	"${cluster}" != "mainnet-beta" ]]; then
	echo "Only valid cluster values are 'devnet' and 'mainnet'/'mainnet-beta'"
	exit 1
fi

queueKey=""
guardianQueueKey=""
if [[ "${cluster}" == "devnet" ]]; then
	queueKey="FfD96yeXs4cxZshoPPSKhSPgVQxLAJUT3gefgh84m1Di"
	guardianQueueKey="Did69tHXs3NTTomR4ZBzttKjB6W3dssavL8uafVbJ1Q"
elif [[ "${cluster}" == "mainnet-beta" || "${cluster}" == "mainnet" ]]; then
	queueKey="A43DyUGA7s8eXPxqEjJY6EBu1KKbNgfxF8h17VAHn13w"
	guardianQueueKey="B7WgdyAgzK7yGoxfsBaNnY6d41bTybTzEh4ZuQosnvLK"
fi

echo "==================================================="
echo "=                !!! IMPORTANT !!!                ="
echo "=  YOU ARE NOW IN A TEMPORARY CONTAINER. PLEASE   ="
echo "=  FOLLOW THE INSTRUCTIONS BELOW AND THE DOCS.    ="
echo "==================================================="
echo " "

if [[ -z "$(which sb)" ]]; then
	echo " "
	echo "Installing Switchboard CLI now... please wait."
	echo "This step usually takes about 2 minutes."
	npm i -g "@switchboard-xyz/cli@3.4.0" >/dev/null 2>&1
fi

echo " "
export register_guardian=""
while [[ "${register_guardian}" != "y" &&
	"${register_guardian}" != "Y" &&
	"${register_guardian}" != "n" &&
	"${register_guardian}" != "N" ]]; do
	echo -n "Did you also register a guardian, in addition to the oracle? (y/n) "
	read -r register_guardian
done

echo "==================================================="
echo "=       CHECKING THAT YOUR ORACLE IS WORKING      ="
echo "==================================================="
echo " "
echo "Oracle being checked:"
echo "  -> Solana cluster: ${cluster}"
echo "  -> queueKey: ${queueKey}"

echo " "
if [[ "${cluster}" == "devnet" ]]; then

	sb solana on-demand queue \
		print "${queueKey}"

elif [[ "${cluster}" == "mainnet" ||
	"${cluster}" == "mainnet-beta" ]]; then

	sb solana on-demand queue \
		print "${queueKey}" \
		--mainnetBeta

fi

if [[ "${register_guardian}" == "y" || "${register_guardian}" == "Y" ]]; then
	echo " "
	echo "==================================================="
	echo "=     CHECKING THAT YOUR GUARDIAN IS WORKING      ="
	echo "==================================================="
	echo " "
	echo "  -> Solana cluster: ${cluster}"
	echo "  -> Guardian queueKey: ${guardianQueueKey}"

	# adding timer to allow RPC to avoid rate limiting
	sleep 5s

	echo " "
	if [[ "${cluster}" == "devnet" ]]; then

		sb solana on-demand queue \
			print "${guardianQueueKey}"

	elif [[ "${cluster}" == "mainnet" ||
		"${cluster}" != "mainnet-beta" ]]; then

		sb solana on-demand queue \
			print "${guardianQueueKey}" \
			--mainnetBeta

	fi
fi

echo " "
echo "==================================================="
echo "=                !!! IMPORTANT !!!                ="
echo "=  COPY/SAVE THE OUTPUT ABOVE, BEFORE PROCEEDING  ="
echo "=  THEN TYPE 'exit' TO LEAVE THIS TMP CONTAINER.  ="
echo "==================================================="
echo " "
