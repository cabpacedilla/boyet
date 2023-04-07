#!/usr/bin/bash
# This script will automatically upgrade upgradeable packages.
# This code was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.

# Steps
# Add the script in autostart after saving.

#!/usr/bin/bash
while true; do

notify-send "Checking system updates."

UPGRADEABLE=$(sudo apt update | tail -n1)
LIST=~/bin/upgradeable.txt
DATE=$(date | awk '{print $2}')

if [ "$DATE" = "30" ] || [ "$DATE" = "15" ]; then	
	if [ "$UPGRADEABLE" = "All packages are up to date." ]; then
		notify-send "System is up to date."
	else 
		PACKAGES=$(apt list --upgradable | tail -n +2 > "$LIST")
		PACKAGES=$(cut -d/ -f1 "$LIST")
		notify-send "$PACKAGES to be updated."	
		notify-send "Updating $PACKAGES..."	
		if sudo apt -y upgrade; then
			notify-send "Auto-removing and auto-cleaning package updates"
			sudo apt -y autoremove; 
			sudo apt autoclean
			notify-send "$PACKAGES were updated."
		else
			notify-send "Upgrade was unsuccessful."
		fi 
	fi
else
	notify-send "Date is not 15 or 30"
fi

sleep 7h
done
