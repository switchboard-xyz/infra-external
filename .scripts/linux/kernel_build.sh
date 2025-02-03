#!/usr/bin/env bash
set -eu
TMPDIR="$(mktemp -d)"

echo "Updating OS and installing needed tools"
apt update &&
  apt install -y \
    build-essential libncurses-dev gawk flex bison openssl libssl-dev \
    dkms libelf-dev libudev-dev libpci-dev libiberty-dev autoconf llvm

echo "cloning AMD SNP kernel in tmp directory ${TMPDIR}"
cd "${TMPDIR}" &&
  git clone \
    https://github.com/confidential-containers/linux \
    --single-branch \
    -b amd-snp-host-202402240000 \
    "${TMPDIR}/linux"

VER="-snp-host"
DATE="$(date +%Y-%m-%d-%H-%M)"

echo "building and installing kernel... this will take while"
echo "Copying current config to new kernel"
cd "${TMPDIR}"/linux &&
  cp /boot/config-$(uname -r) .config

echo "Patching new kernel"
cd "${TMPDIR}"/linux &&
  ./scripts/config --set-str LOCALVERSION "$VER-$DATE" &&
  ./scripts/config --disable LOCALVERSION_AUTO &&
  ./scripts/config --enable DEBUG_INFO &&
  ./scripts/config --enable DEBUG_INFO_REDUCED &&
  ./scripts/config --enable EXPERT &&
  ./scripts/config --enable AMD_MEM_ENCRYPT &&
  ./scripts/config --disable AMD_MEM_ENCRYPT_ACTIVE_BY_DEFAULT &&
  ./scripts/config --enable KVM_AMD_SEV &&
  ./scripts/config --module CRYPTO_DEV_CCP_DD &&
  ./scripts/config --disable SYSTEM_TRUSTED_KEYS &&
  ./scripts/config --disable SYSTEM_REVOCATION_KEYS &&
  ./scripts/config --module SEV_GUEST &&
  ./scripts/config --disable IOMMU_DEFAULT_PASSTHROUGH

echo "Building new kernel"
cd "${TMPDIR}"/linux &&
  yes "" | make olddefconfig &&
  make -j$(nproc) LOCAL_VERSION="$VER-$DATE" &&
  make -j$(nproc) modules_install &&
  make -j$(nproc) install

echo "Kernel Built, configuring and updating GRUB"
sed -i 's/iommu=pt/iommu=nopt/g' /etc/default/grub &&
  update-grub &&
  rm -rf "${TMPDIR}"

echo "cleaning kernel tmp directory ${TMPDIR}"
echo "Work completed. You should now reboot."
