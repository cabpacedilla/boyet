#!/usr/bin/bash 
while true; do

# Create a shortcut key with command 

RECENT_LIST=~/bin/recentFiles.txt
RECENTLY_USED=~/.local/share/recently-used.xbel

RECENT_FILES=$(awk -F"file://|\" " '/file:\/\// {print $2}' "$RECENTLY_USED")

echo "$RECENT_FILES" > "$RECENT_LIST"

RECENTS=$(cat "$RECENT_LIST" | tail)

echo "$RECENTS" > "$RECENT_LIST"

declare -a RECENTARR=()
while read -r line; do      
	RECENTARR+=($line)
done < "$RECENT_LIST"

#echo "${RECENTARR[@]}"

cat "$RECENT_LIST" | tail 

echo "Please provide the sequence number of the accessed file: "

read OPEN_FILE

file=$(echo "${RECENTARR[$OPEN_FILE]}" | sed 's/%20/\\ /g' | sed 's/%2520/\\ /g')
file=$(echo "$file" | xargs)

xdg-open "$file"

done
