#!/usr/bin/env bash
set -u -e

cd "$(pwd)/../../../.scripts/docker-compose/"
sed -i 's?.*#.*-.*devnet/docker-compose.yml.*?  - devnet/docker-compose.yml?g' docker-compose.yml
