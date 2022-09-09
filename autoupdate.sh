#!/usr/bin/bash
# This script will automatically upgrade upgradeable packages.
# This code was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.

# Steps
# 1. Set apt with no password requirement with the user account in sudoers file
#    {user} ALL=(ALL) NOPASSWD: /usr/bin/apt
# 2. Set a cron job for the script
#    30 1 1,15 * * ~/bin/autoupdate.sh

UPGRADEABLE=$(sudo apt update | grep "packages can be upgraded")
PACKAGENUM=$(echo $UPGRADEABLE | awk '{print $1}')

if [ -n "$UPGRADEABLE" ]; then
	sudo apt list --upgradeable > ~/bin/upgradeable.txt
	PACKAGES=$(cut -d/ -f1 upgradeable.txt)
  	notify-send "Upgrading $PACKAGES"
	sudo apt upgrade
	
else
	notify-send "No upgradeable packages."
	
fi
	
