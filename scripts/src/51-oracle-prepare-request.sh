queueKey="${1:-5Qv744yu7DmEbU669GmYRqL9kpQsyYsaVKdR8YiBMTaP}"
guardianQueue="${2:-71wi6H1ByDG9qnRd5Ef8PSKoKH8rJ7pve7NDvB7Y4tqi}"

echo "Creating new Oracle/Guardian acceptance request on Solana for:"
echo "queueKey: ${queueKey}"
echo "guardianQueue: ${guardianQueue}"

npm i -g ts-node >/dev/null 2>&1 &&
	npm i >/dev/null 2>&1

ts-node ./bootstrap.ts \
	--queueKey "$queueKey" \
	--guardianQueue "$guardianQueue" \
	--payerPath payer.json

echo "!!! IMPORTANT !!!"
echo "SAVE THE OUTPUT from the command above before proceeding."

echo " "
echo "Should be safe to exit now. Just type 'exit' from this temporary container."
