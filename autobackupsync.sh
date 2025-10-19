#!/usr/bin/env bash
# Set user in /etc/sudoers file without providing password with rsync command
# add line <username> ALL=(ALL) NOPASSWD: /usr/bin/rsync
ORIGIN=~/Documents/
DESTINATION=/run/media/claiveapa/Data/claive/Documents/nobara/
while inotifywait -r -e modify,create $ORIGIN; do
	TIME=$(date +"%I:%M %p")
	rsync -avz --protect-args "$ORIGIN" "$DESTINATION"
	if [ $? = 0 ]; then
		notify-send --app-name "Auto-backup:    $TIME" "Backup sync was successful."
	else
		notify-send --app-name "Auto-backup:    $TIME""Backup sync encountered an error."
	fi
   #sudo rsync -avHAX ~/Documents/testfiles/ /mnt/backup/ --delete
   #sudo tar cvf /mnt/backup/tarball$DATE ~/Documents/testfiles/*
done
