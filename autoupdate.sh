#!/usr/bin/bash
# This script will automatically upgrade upgradeable packages.
# This code was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.

# Steps
# Add the script in autostart after saving.

#!/usr/bin/bash
while true; do

notify-send "Auto-updates:" "Checking updates."

UPGRADEABLE=$(sudo apt update | grep "packages can be upgraded.")
#DATE=$(date | awk '{print $2}')
LIST=~/bin/upgradeable.txt

#if [ "$DATE" = "30" ] || [ "$DATE" = "15" ]; then
if [ -z "$UPGRADEABLE" ]; then
	notify-send "Auto-updates:" "No upgradeable packages."
elif [ -n "$UPGRADEABLE" ]; then
	sudo apt list --upgradeable | tail -n +2 > "$LIST"
	PACKAGES=$(cut -d/ -f1 "$LIST")
	notify-send "Auto-updates:" "$PACKAGES to be updated."	
	notify-send "Updating $PACKAGES..."	
	if gnome-terminal -- sudo apt upgrade -y && yes | sudo apt autoremove; then
	   notify-send "Auto-updates:" "$PACKAGES were updated."
	else
	   notify-send "Auto-updates:" "Upgrade was unsuccessful."
	fi 
else
:
fi

sleep 7h
done
