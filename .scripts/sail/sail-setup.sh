# kernel
TMPDIR="$(mktemp -d)"
wget -q 'https://sapphire-perfect-gerbil-428.mypinata.cloud/ipfs/bafybeiefyfwhxurut6n4wvz53zad5ffyt7vrllq5eomv6nejvqqlosbfpi' -O "${TMPDIR}/sb-sail-kernel.tar.xz"

#initrd
wget -q 'https://sapphire-perfect-gerbil-428.mypinata.cloud/ipfs/bafybeibqtndt7xeaasrbg5fkvdv24jysjkzxna3rgjum5fxpxamojhxclu' -O "${TMPDIR}/sb-sail-initrd.tar.xz"

tar -x "${TMPDIR}/sb-sail-kernel.tar.xz" -C /opt/kata/share/kata-containers/
tar -x "${TMPDIR}/sb-sail-initrd.tar.xz" -C /opt/kata/share/kata-containers/

sed -i '' /opt/kata/share/defaults/kata-containers/configuration-qemu-snp.toml
sed -i 's?^initrd =.*?initrd = /opt/kata/share/kata-containers/sb-sail-initrd?g' /opt/kata/share/defaults/kata-containers/configuration-qemu-snp.toml
sed -i 's?^kernel =.*?kernel = /opt/kata/share/kata-containers/sb-sail-kernel?g' /opt/kata/share/defaults/kata-containers/configuration-qemu-snp.toml
