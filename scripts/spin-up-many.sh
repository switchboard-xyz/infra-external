#!/bin/bash

# Path to your Helm chart
CHART_PATH="../charts/pull-service"

# Path to your text file
FILE_PATH="./oracle-keys.txt"

VALUE_PATH="../chains/solana/values.yaml"

counter=0

while IFS= read -r line
do
  counter=$((counter+1))
  NAMESPACE="oracle-$counter"
  HOST="oracle-$line.switchboard.xyz"
  DEPLOYMENT_NAME="pull-oracle-$line"

  echo "Deploying Helm chart for $NAMESPACE"

  helm upgrade --install "$DEPLOYMENT_NAME" "$CHART_PATH" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --set namespace="$NAMESPACE" \
    --set host="$HOST" --dry-run \
    --set components.oracle.key="$line" \
    -f "$VALUE_PATH"

done < "$FILE_PATH"
