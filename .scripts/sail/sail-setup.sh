TMPDIR="$(mktemp -d)"

cd "${TMPDIR}"
wget -q 'https://sapphire-perfect-gerbil-428.mypinata.cloud/ipfs/bafybeiebhqp5ckhzqdumua5swmqihacsap7w7kz5cu7kbgd35bxsckp7sq' -O "${TMPDIR}/sb-sail-initrd"
wget -q 'https://sapphire-perfect-gerbil-428.mypinata.cloud/ipfs/bafybeidpqahfmvugxxizufa6aabefrv53e7cr5dtfccmkbme7jsmlz3zvq' -O "${TMPDIR}/sb-sail-kernel"

sha256sum "${TMPDIR}/sb-sail-kernel"
sha256sum "${TMPDIR}/sb-sail-initrd"

mv ./sb-sail* /opt/kata/share/kata-containers/

sed -i 's?^initrd =.*?initrd = "/opt/kata/share/kata-containers/sb-sail-initrd"?g' /opt/kata/share/defaults/kata-containers/configuration-qemu-snp.toml
sed -i 's?^kernel =.*?kernel = "/opt/kata/share/kata-containers/sb-sail-kernel"?g' /opt/kata/share/defaults/kata-containers/configuration-qemu-snp.toml

rm -rf "${TMPDIR}"
