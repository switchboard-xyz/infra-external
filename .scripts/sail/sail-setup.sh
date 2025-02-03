TMPDIR="$(mktemp -d)"

cd "${TMPDIR}"
wget -q 'https://sapphire-perfect-gerbil-428.mypinata.cloud/ipfs/bafybeiefyfwhxurut6n4wvz53zad5ffyt7vrllq5eomv6nejvqqlosbfpi' -O "${TMPDIR}/sb-sail-kernel.tar.xz"
wget -q 'https://sapphire-perfect-gerbil-428.mypinata.cloud/ipfs/bafybeibqtndt7xeaasrbg5fkvdv24jysjkzxna3rgjum5fxpxamojhxclu' -O "${TMPDIR}/sb-sail-initrd.tar.xz"

tar --transform 's/.*/sb-sail-initrd/' -xf "${TMPDIR}/sb-sail-initrd.tar.xz" ./opt/kata/share/kata-containers/kata-ubuntu-20.04-confidential.initrd
tar --transform 's/.*/sb-sail-kernel/' -xf "${TMPDIR}/sb-sail-kernel.tar.xz" ./opt/kata/share/kata-containers/vmlinuz-6.12.8-142-confidential

mv ./sb-sail* /opt/kata/share/kata-containers/

sed -i 's?^initrd =.*?initrd = /opt/kata/share/kata-containers/sb-sail-initrd?g' /opt/kata/share/defaults/kata-containers/configuration-qemu-snp.toml
sed -i 's?^kernel =.*?kernel = /opt/kata/share/kata-containers/sb-sail-kernel?g' /opt/kata/share/defaults/kata-containers/configuration-qemu-snp.toml

rm -rf "${TMPDIR}"
