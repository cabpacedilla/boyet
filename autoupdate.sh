#!/usr/bin/bash
# This script will automatically upgrade upgradeable packages.
# This code was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.

# Steps
# 1. Set apt with no password requirement with the user account in sudoers file
#    {user} ALL=(ALL) NOPASSWD: /usr/bin/apt
# 2. Set a cron job for the script
#    30 1 1,15 * * /home/{user}/bin/autoupdate.sh

#!/usr/bin/bash

UPGRADEABLE=$(sudo apt update | grep "packages can be upgraded.")
DATE=$(date | awk '{print $2}')
LIST=~/bin/upgradeable.txt

if [ "$DATE" = "01" ] || [ "$DATE" = "15" ]; then
if [ -n "$UPGRADEABLE" ]; then
	sudo apt list --upgradeable | tail -n +2 > $LIST
	PACKAGES=$(cut -d/ -f1 $LIST)
  	notify-send "Auto-updates:" "Upgrading $PACKAGES"
	yes | sudo apt upgrade
	if [ $? -eq 0 ]; then
    	notify-send "Auto-updates:" "$PACKAGES were updated."
    else
    	notify-send "Auto-updates:" "Upgrade was unsuccessful."
    fi 

else
	notify-send "Auto-updates:" "No upgradeable packages."
	
fi

else
 :
fi

sleep 7h
