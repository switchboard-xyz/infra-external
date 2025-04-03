#!/usr/bin/env bash
set -eu

REPO_DIR="$(realpath ../../../)"
STATIC_FILES_DIR="${REPO_DIR}/.static"

dpkg -i ${STATIC_FILES_DIR}/linux*6.8.0*.deb

echo "Kernel installed and configured. Updating GRUB now."
sed -i 's/iommu=pt/iommu=nopt/g' /etc/default/grub &&
  update-grub 2>/dev/null &&
  rm -rf "${TMPDIR}"

echo "Cleaning kernel tmp directory ${TMPDIR}"
echo "Work completed. You should now reboot."
