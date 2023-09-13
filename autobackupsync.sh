#!/usr/bin/sh

# Set user in /etc/sudoers file without providing password with rsync command
# add line <username> ALL=(ALL) NOPASSWD: /usr/bin/rsync

# Needs filesystem change monitoring tool like inotify in Linux

while inotifywait -r -e modify,create,delete ~/<sourcefolder>
do
   notify-send "Folder updated. Syncing folder."
	rsync -avl /home/boyet/Documents/claive/ /media/boyet/Data/claive --delete
	if [ $? = 0 ]; then
		notify-send "Backup sync was successful."
	else
		notify-send "Backup sync encountered an error."
	fi
done
