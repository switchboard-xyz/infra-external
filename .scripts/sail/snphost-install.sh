#!/usr/bin/env bash
set -eu

snphost_binary="/usr/local/bin/snphost"

wget -q 'https://sapphire-perfect-gerbil-428.mypinata.cloud/ipfs/bafybeiatox2alhmpm3hy4mvvonzzdkkq3mvp3zskvjztnsat2jbnryuikq' -O "${snphost_binary}"

chmod 755 "${snphost_binary}"

echo "SNPHOST installed in /usr/local/bin/snphost"
