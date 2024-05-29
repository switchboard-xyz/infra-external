#!/usr/bin/env bash
set -u -e

docker compose --env-file ../../cfg/00-vars.cfg "$@"
