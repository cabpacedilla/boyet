#!/usr/bin/bash
# This script will automatically upgrade upgradeable packages.
# This code was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.

# Steps
# Add the script in autostart after saving.

#!/usr/bin/bash
while true; do

notify-send "Auto-updates:" "Checking updates."

UPGRADEABLE=$(sudo apt update | tail -n1)
LIST=~/bin/upgradeable.txt
DATE=$(date | awk '{print $2}')

if [ "$DATE" = "15" ] || [ "$DATE" = "30" ]; then	
	if [ "$UPGRADEABLE" = "All packages are up to date." ]; then
		notify-send "System is up to date."
	else 
		PACKAGES=$(apt list --upgradable | tail -n +2 > "$LIST")
		PACKAGES=$(cut -d/ -f1 "ST")
		notify-send "$PACKAGES to be updated."	
		notify-send "Updating $PACKAGES..."	
		if gnome-terminal -- sudo apt upgrade -y && sudo apt autoremove -y && sudo apt autoclean; then
			notify-send "Autoremoving and autocleaning unneeded packages" && notify-send "$PACKAGES were updated."
		else
			notify-send "Upgrade was unsuccessful."
		fi 
	
	fi
fi

sleep 7h
done
