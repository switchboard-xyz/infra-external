#!/usr/bin/env bash
set -eu

TMPDIR="$(mktemp -d)"

cd "${TMPDIR}"
wget -q 'https://sapphire-perfect-gerbil-428.mypinata.cloud/ipfs/bafybeigbu4v6ofuoolix2oesdx37sdqtgdvyju3tfrtyxu3fmylivpet4e' -O "${TMPDIR}/sb-linux-headers-6.8.0.deb"
wget -q 'https://sapphire-perfect-gerbil-428.mypinata.cloud/ipfs/bafybeiczzzld5yybghmb56a5ari4b5y4i7pcwc22y7xfqhstcqnuanlcie' -O "${TMPDIR}/sb-linux-image-6.8.0.deb"
wget -q 'https://sapphire-perfect-gerbil-428.mypinata.cloud/ipfs/bafybeifkhsbc6ec2cdulkwwikiodj5ylei733jpyzgeqrpiccw2cj5b6i4' -O "${TMPDIR}/sb-linux-image-dbg-6.8.0.deb"
wget -q 'https://sapphire-perfect-gerbil-428.mypinata.cloud/ipfs/bafybeiao732b3tzaolbq2qftn5vkla7vldbwgvwbfoen3ckpm5y2pqxp6u' -O "${TMPDIR}/sb-linux-libc-dev-6.8.0.deb"

dpkg -i "${TMPDIR}"/*deb

rm -rf "${TMPDIR}"

echo "Kernel installed and configured. Updating GRUB now."
sed -i 's/iommu=pt/iommu=nopt/g' /etc/default/grub &&
  update-grub &&
  rm -rf "${TMPDIR}"

echo "Cleaning kernel tmp directory ${TMPDIR}"
echo "Work completed. You should now reboot."
