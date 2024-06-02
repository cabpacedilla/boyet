#!/usr/bin/sh

# Set user in /etc/sudoers file without providing password with rsync command
# add line <username> ALL=(ALL) NOPASSWD: /usr/bin/rsync at the bottom of the /etc/sudoers file using sudo visudo

# Needs filesystem change monitoring tool like inotify in Linux

# while inotifywait -r -e modify,create,delete ~/<sourcefolder> ~/<sourcefolder> 
while inotifywait -r -e modify,create,delete /home/boyet/Documents/claive/ /home/boyet/bin/
do
   notify-send "Folder updated. Syncing folder."
	#rsync -avl /home/boyet/Documents/claive/ /media/boyet/Data/claive --delete
 	sudo rsync -avhP /home/boyet/Documents/claive/ /home/boyet/bin/ /media/boyet/Data/claive
	if [ $? = 0 ]; then
		notify-send "Backup sync was successful."
	else
		notify-send "Backup sync encountered an error."
	fi
done
