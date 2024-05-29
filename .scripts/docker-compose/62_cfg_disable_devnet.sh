#!/usr/bin/env bash
set -u -e

cd ../../.scripts/docker-compose/
sed -i 's/.*-.*devnet.*/  #- devnet/g' docker-compose.yml
