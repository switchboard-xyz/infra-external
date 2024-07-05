#!/usr/bin/env bash
set -u -e

cd "$(pwd)/../../../.scripts/docker-compose/"
sed -i 's?.*#.*-.*common/watchtower.yml.*?  - common/watchtower.yml?g' docker-compose.yml
