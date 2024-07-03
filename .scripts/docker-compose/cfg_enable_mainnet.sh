#!/usr/bin/env bash
set -u -e

cd "$(pwd)/../../../.scripts/docker-compose/"
sed -i 's?.*#.*-.*mainnet/docker-compose.yml.*?  - mainnet/docker-compose.yml?g' docker-compose.yml

sed -i 's?.*#.*mainnet:.*?  mainnet:?g' common/networks.yml
