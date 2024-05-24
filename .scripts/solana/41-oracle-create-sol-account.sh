apt-get update >/dev/null 2>&1 &&
	apt-get install -y ca-certificates >/dev/null 2>&1

PAYER_FILE="/data/payer.json"

solana-keygen new --word-count 24 -o "${PAYER_FILE}"

echo "!!! IMPORTANT !!!"
echo "SAVE THE 24 WORDS ABOVE OR YOU MAY LOSE ALL YOUR FUNDS!!!"
echo " "
echo "Also save the following string (your SOL account private key) and NEVER SHOW to anyone."

cat "${PAYER_FILE}"

echo " "
echo "Requesting funding of 5 SOL on devnet:"
solana airdrop 5 -u devnet -k "${PAYER_FILE}"

echo " "
echo "Checking current balance for your new account:"
solana balance -u devnet -k "${PAYER_FILE}"

echo " "
echo "Should be safe to exit now. Just type 'exit' from this temporary container."
