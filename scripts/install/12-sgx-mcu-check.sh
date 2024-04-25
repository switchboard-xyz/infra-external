#!/usr/bin/env bash
set -u -e

echo -n "Your current version of CPU microcode is: "

cat /proc/cpuinfo | grep microcode | sort | uniq

echo " "
echo "Saving this output to a file in /root/new_microcode_version.txt"

echo " "
echo -n "Is this a later version than your old one: "
cat /root/old_microcode_version.txt

echo "Also check the output from your kernel boot output to verify"
echo "if there were any errors during the microcode update:"

dmesg | grep microcode # should see logs from the outpout

echo " "
echo "If everything looks good, you can continue with the setup."
