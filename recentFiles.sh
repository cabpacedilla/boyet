#!/usr/bin/bash 
while true; do

# Create a shortcut key with command qterminal -e recentFiles.sh

RECENT_LIST=~/bin/recentFiles.txt
REVERSE_LIST=~/bin/reverseRecent.txt
RECENTLY_FILE=~/.local/share/recently-used.xbel

RECENT_FILES=$(awk -F"file://|\" " '/file:\/\// {print $2}' "$RECENTLY_FILE")
RECENT_FILES_CLEAN=$(awk -F"file://|\" " '/file:\/\// {print $2}' "$RECENTLY_FILE" | sed 's/%20/\ /g')

echo "$RECENT_FILES" > "$RECENT_LIST"

RECENTS=$(cat "$RECENT_LIST" | tail)

echo "$RECENTS" > "$RECENT_LIST"

declare -a RECENTARR=()
while read -r line; do      
	RECENTARR+=($line)
done < "$RECENT_LIST"

#echo "${RECENTARR[@]}"

echo "$RECENT_FILES_CLEAN" | tail > "$REVERSE_LIST"
REVERSE_LIST=$(nl "$REVERSE_LIST")
echo "$REVERSE_LIST"

echo "Please provide the sequence number of the accessed file: "

read OPEN_FILE

FILE=$(echo "${RECENTARR[${OPEN_FILE} - 1]}" | sed 's/%20/\\ /g' | sed 's/%2520/\\ /g')
FILE=$(echo "$FILE" | xargs)

xdg-open "$FILE"

done


