#!/usr/bin/bash
#install first kqueue in BSD systems or inotify-tools in Linux

while fswatch -1 ~/Documents/testfiles
do    
   sudo rsync -avz ~/Documents/testfiles/* /mnt/backup/      
done
