#!/usr/bin/env bash
set -u -e

cd "$(pwd)/../../../.scripts/docker-compose/"
sed -i 's?.*#.*-.*devnet/docker-compose.yml.*?  - devnet/docker-compose.yml?g' docker-compose.yml

sed -i 's?.*#*.*devnet:.*?  devnet:?g' common/networks.yml

sed -i 's?^.*#*.*- devnet.*$?      - devnet?g' common/webserver.yml

echo " "
echo "DEVNET environment - ENABLED"
echo " "
