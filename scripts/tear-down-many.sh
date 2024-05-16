#!/bin/bash

# Get the list of all Helm deployments
DEPLOYMENTS=$(helm list --short)

# Iterate over each deployment
for DEPLOYMENT in $DEPLOYMENTS
do
  # Check if the deployment name starts with "oracle-"
  if [[ $DEPLOYMENT == pull-oracle-* ]]
  then
    echo "Deleting Helm deployment $DEPLOYMENT"
    helm uninstall "$DEPLOYMENT"
  fi
done
