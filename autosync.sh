#!/usr/bin/sh

# fswatch needs filesystem change monitoring tool like inotify in Linux
#DATE=`date | awk '{print $2$3$4$5$6}'`

#while fswatch -1 ~/Documents/testfiles

while inotifywait -e modify ~/Documents
do
   sudo rsync -avHAX ~/<sourcefolder>/ /<destinationfolder>/ --delete

   #sudo rsync -avHAX ~/Documents/testfiles/ /mnt/backup/ --delete
   #sudo tar cvf /mnt/backup/tarball$DATE ~/Documents/testfiles/*

done
