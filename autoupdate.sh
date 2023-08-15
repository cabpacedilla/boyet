#!/usr/bin/bash
# This script will automatically upgrade upgradeable packages.
# This code was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.

# Steps
# Add the script in autostart after saving.

#!/usr/bin/bash
while true; do

LIST=~/bin/upgradeable.txt
DATE=$(date | awk '{print $2}')

if [ "$DATE" = "15" ] || [ "$DATE" = "30" ]; then
	notify-send --app-name "Auto-updates:" "Checking system updates."
	UPGRADES=$(/usr/lib/update-notifier/apt-check |& cut -d";" -f 1 &)
	if [ "$UPGRADES" -gt 0 ]; then
	  	sudo apt update
     		sudo apt list --upgradable | tail -n +2 > "$LIST"
    		PACKAGES=$(cut -d/ -f1 "$LIST")
     		if [ -n "$PACKAGES" ]; then
			notify-send --app-name "Auto-updates:" "$PACKAGES to be updated."   
			notify-send --app-name "Auto-updates:" "Updating $PACKAGES..."   
			if sudo apt -y upgrade; then
				notify-send --app-name "Auto-updates:" "Auto-removing and auto-cleaning package updates"
				sudo apt -y autoremove;
				sudo apt autoclean
				notify-send --app-name "Auto-updates:" "$PACKAGES were updated. System is up to date."
			else
				notify-send --app-name "Auto-updates:" "Upgrade encountered an error."
			fi
	  	fi
	else
		notify-send --app-name "Auto-updates:" "System is already up to date."
	fi
else
	 notify-send "Auto-updates:" "Date is not 15 or 30"
fi

sleep 2h
done
