cluster="${1:-devnet}"

apt-get update >/dev/null 2>&1 &&
	apt-get install -y ca-certificates >/dev/null 2>&1

solana-keygen new --word-count 24 -o ./payer.json

echo "!!! IMPORTANT !!!"
echo "SAVE THE 24 WORDS ABOVE OR YOU MAY LOSE ALL YOUR FUNDS!!!"
echo " "
echo "Also save the following string (your SOL account private key) and NEVER SHOW to anyone."

cat ./payer.json

# only on devnet
if [[ "${cluster}" == "devnet" ]]; then
	echo " "
	echo "Requesting self-funding of 5 SOL on devnet:"
	solana airdrop 5 -u devnet -k ./payer.json
fi

echo " "
echo "Checking current balance for your new account:"
solana balance -u "${cluster}" -k ./payer.json

echo " "
echo "Should be safe to exit now. Just type 'exit' from this temporary container."
