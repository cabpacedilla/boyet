#!/usr/bin/bash
# This script will automatically upgrade upgradeable packages.
# This code was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.

UPGRADEABLE=$(sudo apt update | grep "packages can be upgraded")
PACKAGENUM=$(echo $UPGRADEABLE | awk '{print $1}')

if [ -n "$UPGRADEABLE" ]; then
        notify-send "Upgrading $PACKAGENUM packages"
        sudo apt upgrade

else
        notify-send "No upgradeable packages."

fi
