#!/usr/bin/env bash
set -u -e

echo -n "Your current version of CPU microcode is: "

grep microcode /proc/cpuinfo | sort -u | awk '{print $NF}'

echo " "
echo -n "This is the old version of CPU microcode: "
cat /root/old_microcode_version.txt

echo "The new version of microcode should be equal or newer to the old one"

echo " "
echo "Also check the output from your kernel boot output to verify"
echo "if there were any errors during the microcode update:"

echo '```'
dmesg | grep microcode # should see logs from the outpout
echo '```'

echo " "
echo "If everything looks good, you can continue with the setup."
