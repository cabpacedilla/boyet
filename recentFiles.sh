#!/usr/bin/env bash

# Infinite loop to continuously check recent files
while true; do

# Define file paths
RECENT_LIST=~/scriptlogs/recentFiles.txt
TAIL_LIST=~/scriptlogs/reverseRecent.txt
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
mapfile -t RECENTARR < "$RECENT_LIST"

# Add line numbers
echo "$RECENT_FILES_CLEAN" | tail -n 40 > "$TAIL_LIST"
RECENT_FILES_CLEAN=$(nl "$TAIL_LIST")
echo "$RECENT_FILES_CLEAN"

# Prompt the user to select a file
echo "Please provide the sequence number of the accessed file: "
read -r OPEN_FILE

# Validate user input
if { [ -n "${OPEN_FILE//[0-9]/}" ]; } || { [ "$OPEN_FILE" -lt "1" ] || [ "$OPEN_FILE" -gt "${#RECENTARR[@]}" ]; }; then
	notify-send "Invalid input. Please enter a valid sequence number." &
	continue
fi

# Get the selected file and clean up any escaped characters
FILE=$(echo "${RECENTARR[OPEN_FILE - 1]}" | sed 's/%20/ /g' | sed 's/%2520/ /g')
FILE=$(echo "$FILE" | xargs)

# Check if the file exists before attempting to open it
if [ -f "$FILE" ]; then
	# Open the selected file
	xdg-open "$FILE" &
else
	notify-send "File does not exist: $FILE" &
fi

done
