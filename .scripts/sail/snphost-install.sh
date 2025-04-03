#!/usr/bin/env bash
set -u -e

REPO_DIR="$(realpath ../../../)"
STATIC_FILES_DIR="${REPO_DIR}/.static"

snphost_binary="/usr/local/bin/snphost"

cp ${STATIC_FILES_DIR}/snphost ${snphost_binary}

chmod 755 "${snphost_binary}"

echo "SNPHOST installed in /usr/local/bin/snphost"
