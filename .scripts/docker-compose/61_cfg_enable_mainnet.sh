#!/usr/bin/env bash
set -u -e

cd ../../.scripts/docker-compose/
sed -i 's/.*#.*-.*mainnet.*/  #- mainnet/g' docker-compose.yml
