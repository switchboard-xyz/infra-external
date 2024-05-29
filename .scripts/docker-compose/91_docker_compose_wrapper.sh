#!/usr/bin/env bash
set -u -e

cd "$(pwd)/../../../.scripts/docker-compose/"
docker compose --env-file ../../cfg/00-common-vars.cfg "$@"
