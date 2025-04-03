#!/usr/bin/env bash
set -u -e

REPO_DIR="$(realpath ../../../)"
STATIC_FILES_DIR="${REPO_DIR}/.static"

cp ${STATIC_FILES_DIR}/sb-sail* /opt/kata/share/kata-containers/

sed -i 's?^initrd =.*?initrd = "/opt/kata/share/kata-containers/sb-sail-initrd"?g' /opt/kata/share/defaults/kata-containers/configuration-qemu-snp.toml
sed -i 's?^kernel =.*?kernel = "/opt/kata/share/kata-containers/sb-sail-kernel"?g' /opt/kata/share/defaults/kata-containers/configuration-qemu-snp.toml

echo "SB SAIL kernel and initrd installed"
