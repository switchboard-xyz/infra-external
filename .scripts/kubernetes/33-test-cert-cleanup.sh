#!/usr/bin/env bash
set -u -e

kubectl delete -f testcert.yml

rm -f ./testcert.yml
