#!/usr/bin/sh
# Set user in /etc/sudoers file without providing password with rsync command
# add line <username> ALL=(ALL) NOPASSWD: /usr/bin/rsync
#while inotifywait -e modify,create /home/capa/Documents/ /home/capa/bin/
while inotifywait -r -e modify,create /home/capa/Documents/ /home/capa/bin/
do
	TIME=$(date +"%I:%M %p")
	#notify-send --app-name "Auto-backup:    $TIME" "Folder updated. Syncing folder."
	#rsync -avHAXS /home/boyet/Documents/claive/ /home/boyet/Documents/backup
	#rsync -avz /home/boyet/Documents/claive/ /home/boyet/Documents/backup --delete
	#rsync -avuhP /home/boyet/Documents/claive/ /home/boyet/bin/ /media/boyet/Data/claive
	sudo rsync -avuhPHAXS /home/capa/Documents /home/capa/bin /run/media/capa/sda1/claive
	if [ $? = 0 ]; then
		notify-send --app-name "Auto-backup:    $TIME" "Backup sync was successful."
	else
		notify-send --app-name "Auto-backup:    $TIME""Backup sync encountered an error."
	fi
   #sudo rsync -avHAX ~/Documents/testfiles/ /mnt/backup/ --delete
   #sudo tar cvf /mnt/backup/tarball$DATE ~/Documents/testfiles/*

done
