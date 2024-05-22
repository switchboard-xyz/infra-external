#!/usr/bin/env bash
set -u -e

# import vars
source ./00-vars.cfg

kubectl delete -f testcert.yml

rm -f ./testcert.yml
