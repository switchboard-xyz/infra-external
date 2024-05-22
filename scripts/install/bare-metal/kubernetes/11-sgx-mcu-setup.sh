#!/usr/bin/env bash
set -u -e

echo "Your current version of CPU microcode is: "

cat /proc/cpuinfo | grep microcode | sort | uniq

echo " "
echo "Saving this output to a file in /root/old_microcode_version.txt"
echo "so that it can be checked later to verify it got updated."

cat /proc/cpuinfo | grep microcode | sort | uniq >/root/old_microcode_version.txt

echo " "
echo "Setting up Microcode Update (MCU) now"
echo " "
mkdir /tmp/MCU
git clone https://github.com/intel/Intel-Linux-Processor-Microcode-Data-Files.git /tmp/MCU/data
cd /tmp/MCU/data && git checkout microcode-20240312          # adjust according to latest tag
rsync -ravP /lib/firmware/intel-ucode/ /root/intel-ucode.old # backup old microcode

rsync -ravP /tmp/MCU/data/intel-ucode/ /lib/firmware/intel-ucode --delete

update-initramfs -u

echo " "
echo "To finalized the MCU you should 'reboot' your server."
