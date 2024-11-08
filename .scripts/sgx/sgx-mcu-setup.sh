#!/usr/bin/env bash
set -u -e

echo -n "Your current version of CPU microcode is: "

grep microcode /proc/cpuinfo | sort -u | awk '{print $NF}'

echo " "
echo "Saving this output to a file in /root/old_microcode_version.txt"
echo "so that it can be checked later to verify it got updated."

grep microcode /proc/cpuinfo | sort -u | awk '{print $NF}' >/root/old_microcode_version.txt

echo " "
echo "Setting up Microcode Update (MCU) now"
echo " "
mkdir /tmp/MCU
git clone -q https://github.com/intel/Intel-Linux-Processor-Microcode-Data-Files.git /tmp/MCU/data >/dev/null
cd /tmp/MCU/data && git checkout microcode-20241029 -q      # adjust according to latest tag
rsync -qra /lib/firmware/intel-ucode/ /root/intel-ucode.old # backup old microcode

rsync -qra /tmp/MCU/data/intel-ucode/ /lib/firmware/intel-ucode --delete

update-initramfs -u

echo " "
echo "To finalized the MCU you should 'reboot' your server."
