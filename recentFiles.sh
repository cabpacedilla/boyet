#!/usr/bin/bash   
# Infinite loop to continuously check recent files
while true; do
	# Define file paths
	RECENT_LIST=~/bin/recentFiles.txt
	REVERSE_LIST=~/bin/reverseRecent.txt
	RECENTLY_FILE=~/.local/share/recently-used.xbel
	
    # Extract recent file paths from the recently-used.xbel file
    RECENT_FILES=$(awk -F 'file://|" ' '/file:\/\// {print $2}' "$RECENTLY_FILE")
    RECENT_FILES_CLEAN=$(echo "$RECENT_FILES" | sed 's/%20/ /g')

    # Save recent files to RECENT_LIST
    echo "$RECENT_FILES" > "$RECENT_LIST"

    # Get the last few recent files
    RECENTS=$(tail -n 40 "$RECENT_LIST")

    # Update RECENT_LIST with recent files
    echo "$RECENTS" > "$RECENT_LIST"

    # Initialize an array to hold recent files
    declare -a RECENTARR=()
    while read -r line; do
        RECENTARR+=("$line")
    done < "$RECENT_LIST"

    # Save cleaned recent files to REVERSE_LIST and number the lines
    echo "$RECENT_FILES_CLEAN" | tail -n 40 > "$REVERSE_LIST"
    REVERSE_LIST=$(nl "$REVERSE_LIST")
    echo "$REVERSE_LIST"

    # Prompt the user to select a file
    echo "Please provide the sequence number of the accessed file: "
    read -r OPEN_FILE

    # Get the selected file and clean up any escaped characters
    FILE=$(echo "${RECENTARR[OPEN_FILE - 1]}" | sed 's/%20/ /g' | sed 's/%2520/ /g')
    FILE=$(echo "$FILE" | xargs)

    # Open the selected file
    xdg-open "$FILE" &

done
