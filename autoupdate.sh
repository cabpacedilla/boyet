#!/usr/bin/bash

UPGRADEABLE=$(sudo apt update | grep "packages can be upgraded")
PACKAGENUM=$(echo $UPGRADEABLE | awk '{print $1}')

if [ -n "$UPGRADEABLE" ]; then
        notify-send "Upgrading $PACKAGENUM packages"
        sudo apt upgrade

else
        notify-send "No upgradeable packages."

fi
