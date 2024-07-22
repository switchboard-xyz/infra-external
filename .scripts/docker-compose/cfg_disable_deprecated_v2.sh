#!/usr/bin/env bash
set -u -e

cd "$(pwd)/../../../.scripts/docker-compose/"
sed -i 's?.*v2/docker-compose.yml.*?  #- v2/docker-compose.yml?g' docker-compose.yml

sed -i 's?^.*#*.*v2:$?  #v2:?g' common/networks.yml
