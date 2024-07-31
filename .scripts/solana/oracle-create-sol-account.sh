cluster="${1:-devnet}"

PAYER_FILE="/data/${cluster}_payer.json"

if [[ "${cluster}" == "mainnet" ]]; then
  cluster="mainnet-beta"
fi

if [[ "${cluster}" != "v2" &&
  "${cluster}" != "devnet" &&
  "${cluster}" != "mainnet" &&
  "${cluster}" != "mainnet-beta" ]]; then
  echo "Only valid cluster values are 'devnet' and 'mainnet'/'mainnet-beta'."
  exit 1
fi

echo " "
echo "==================================================="
echo "=                !!! IMPORTANT !!!                ="
echo "=  YOU ARE NOW IN A TEMPORARY CONTAINER. PLEASE   ="
echo "=  FOLLOW THE INSTRUCTIONS BELOW AND THE DOCS.    ="
echo "==================================================="

echo " "
echo "Installing deps.. usually about 1-2 minutes."
apt-get update >/dev/null 2>&1 &&
  apt-get install -y ca-certificates >/dev/null 2>&1

solana-keygen new --force --word-count 24 -o "${PAYER_FILE}"

cat "${PAYER_FILE}"

echo " "
echo "==================================================="
echo "=                !!! IMPORTANT !!!                ="
echo "= SAVE THE 24 WORDS AND SEQUENCE OF NUMBERS ABOVE ="
echo "= OR YOU MAY LOSE ALL YOUR FUNDS IN FUTURE!!!     ="
echo "= THESE ARE YOUR PRIVATE KEY, KEEP IT SECRET!!!   ="
echo "==================================================="

# only on devnet
if [[ "${cluster}" == "devnet" ]]; then
  echo " "
  echo "Requesting self-funding of 5 SOL on devnet:"
  solana airdrop 5 -u "${cluster}" -k "${PAYER_FILE}"
fi

echo " "
echo "Checking current balance for your new account:"
solana balance -u "${cluster}" -k "${PAYER_FILE}"

echo " "
echo "==================================================="
echo "=                !!! IMPORTANT !!!                ="
echo "=  COPY/SAVE THE OUTPUT ABOVE, BEFORE PROCEEDING  ="
echo "=  THEN TYPE 'exit' TO LEAVE THIS TMP CONTAINER.  ="
echo "==================================================="
echo " "
