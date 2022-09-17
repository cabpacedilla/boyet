#!/usr/bin/bash
# This script will automatically upgrade upgradeable packages.
# This code was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.

# Steps
# 1. Set apt with no password requirement with the user account in sudoers file
#    {user} ALL=(ALL) NOPASSWD: /usr/bin/apt
# 2. Set a cron job for the script
#    30 1 1,15 * * ~/bin/autoupdate.sh

#!/usr/bin/bash

UPGRADEABLE=$(sudo apt update | grep "packages can be upgraded.")

if [ -n "$UPGRADEABLE" ]; then
	sudo apt list --upgradeable | tail -n +2 > ~/bin/upgradeable.txt
	PACKAGES=$(cut -d/ -f1 upgradeable.txt)
  	notify-send "Upgrading $PACKAGES"
	yes | sudo apt upgrade
	if [ $? -eq 0 ]; then
    	notify-send "$PACKAGES were updated."
    else
    	notify-send "Upgrade was unsuccessful."
    fi 
else
	notify-send "No upgradeable packages."
	
fi
	
