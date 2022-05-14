# Set user in /etc/sudoers file without providing password with rsync command
# add line <username> ALL=(ALL) NOPASSWD: /usr/bin/rsync

#!/usr/bin/sh

# fswatch needs filesystem change monitoring tool like inotify in Linux
#DATE=`date | awk '{print $2$3$4$5$6}'`

#while fswatch -1 ~/Documents/testfiles

while inotifywait modify ~/<sourcefolder>
do
   notify-send "Folder updated. Syncing folder."
   sudo rsync -avHAX ~/<sourcefolder> /<destinationfolder> 

   #sudo rsync -avHAX ~/Documents/testfiles/ /mnt/backup/ --delete
   #sudo tar cvf /mnt/backup/tarball$DATE ~/Documents/testfiles/*

done
