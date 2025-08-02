#!/usr/bin/bash
# Set user in /etc/sudoers file without providing password with rsync command
# add line <username> ALL=(ALL) NOPASSWD: /usr/bin/rsync
ORIGIN=~/Documents/
DESTINATION=/run/media/claiveapa/Data/claive/Documents/nobara/
while inotifywait -r -e modify,create $ORIGIN; do
	BACKUP_TIME=$(date +"%I:%M %p")
	rsync -avz --protect-args "$ORIGIN" "$DESTINATION"
	if [ $? = 0 ]; then
		notify-send --app-name "Auto-backup:    $BACKUP_TIME" "Backup sync was successful."
	else
		notify-send --app-name "Auto-backup:    $BACKUP_TIME""Backup sync encountered an error."
	fi
   #sudo rsync -avHAX ~/Documents/testfiles/ /mnt/backup/ --delete
   #sudo tar cvf /mnt/backup/tarball$DATE ~/Documents/testfiles/*
done
