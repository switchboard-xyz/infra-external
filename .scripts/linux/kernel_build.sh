#!/usr/bin/env bash
set -eux
TMPDIR="$(mktemp -d)"

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
(
  cd "${TMPDIR}"/linux &&
    cp /boot/config-$(uname -r) .config
) >/dev/null 2>&1

echo "Patching new kernel"
(
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
) >/dev/null 2>&1

echo "Building new kernel"
(
  cd "${TMPDIR}"/linux &&
    yes "" | make olddefconfig &&
    make -j$(nproc) LOCAL_VERSION="$VER-$DATE" &&
    make -j$(nproc) modules_install &&
    make -j$(nproc) install
) >/dev/null 2>&1

echo "Kernel Built, configuring and updating GRUB"
(
  sed -i 's/iommu=pt/iommu=nopt/g' /etc/default/grub &&
    update-grub &&
    rm -rf "${TMPDIR}"
) >/dev/null 2>&1

echo "cleaning kernel tmp directory ${TMPDIR}"
echo "Work completed. You should now reboot."
