#!/usr/bin/sh

# Set user in /etc/sudoers file without providing password with rsync command
# add line <username> ALL=(ALL) NOPASSWD: /usr/bin/rsync

# Needs filesystem change monitoring tool like inotify in Linux

while inotifywait modify ~/<sourcefolder>
do
   notify-send "Folder updated. Syncing folder."
   sudo rsync -avHAX ~/<sourcefolder> /<destinationfolder> 

   #sudo rsync -avHAX ~/Documents/testfiles/ /mnt/backup/ --delete
   #sudo tar cvf /mnt/backup/tarball$DATE ~/Documents/testfiles/*

done
