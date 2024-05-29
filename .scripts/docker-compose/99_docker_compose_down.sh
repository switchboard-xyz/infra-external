#!/usr/bin/env bash
set -u -e

cd ../../.scripts/docker-compose/
docker compose --env-file ../../cfg/00-vars.cfg down
