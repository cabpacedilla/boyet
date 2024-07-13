#!/usr/bin/env bash
# This script is used to monitor and access recently used files
# This script was assembled written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# June 2024

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
mapfile -t RECENT_ARR < "$RECENT_LIST"

# Add line numbers
echo "$RECENT_FILES_CLEAN" | tail -n 40 > "$TAIL_LIST"
RECENT_FILES_CLEAN=$(nl "$TAIL_LIST")
echo "$RECENT_FILES_CLEAN"

# Prompt the user to select a file
echo "Please provide the sequence number of the accessed file: "
read -r SEQUENCE_NUM

# Validate user input
if { [ -n "${SEQUENCE_NUM//[0-9]/}" ]; } || { [ "$SEQUENCE_NUM" -lt "1" ] || [ "$SEQUENCE_NUM" -gt "${#RECENT_ARR[@]}" ]; }; then
	notify-send "Invalid input. Please enter a valid sequence number." &
	continue
fi

# Get the selected file and clean up any escaped characters
FILE=$(echo "${RECENT_ARR[SEQUENCE_NUM - 1]}" | sed 's/%20/ /g' | sed 's/%2520/ /g')
FILE=$(echo "$FILE" | xargs)

# Check if the file exists before attempting to open it
if [ -f "$FILE" ]; then
	# Open the selected file
	xdg-open "$FILE" &
else
	notify-send "File does not exist: $FILE" &
fi

done
