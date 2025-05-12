#!/usr/bin/env bash
# This script is used to monitor and access recently used files
# This script was assembled written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# June 2024
# call script to launch in a terminal konsole -e /home/claiveapa/Documents/bin/recentFiles.sh

# Define file paths
RECENT_FILES_LIST=~/scriptlogs/recentFiles.txt
TAIL_LIST=~/scriptlogs/reverseRecent.txt
RECENTLY_XBEL_FILE=~/.local/share/recently-used.xbel

# Infinite loop to continuously check recent files
while true; do

	# Ensure the recently-used.xbel file exists
	if [[ ! -f "$RECENTLY_XBEL_FILE" ]]; then
	  notify-send "File $RECENTLY_XBEL_FILE does not exist." &
	  exit 1
	fi

	# Extract recent file paths from the recently-used.xbel file and cleanup path percent encoding
# 	RECENT_FILES=$(awk -F 'file://|" ' '/file:\/\// {print $3}' "$RECENTLY_XBEL_FILE" |
	RECENT_FILES=$(grep -o 'file:///[^"]*' "$RECENTLY_XBEL_FILE" |
  sed 's|file://||' |
  sed -e 's/%0A//g' \
      -e 's/%20/ /g' \
      -e 's/%2F/\//g' \
      -e 's/%3A/:/g' \
      -e 's/%2C/,/g' \
      -e 's/%3F/?/g' \
      -e 's/%23/#/g' \
      -e 's/%26/\&/g' \
      -e 's/%2B/+/g' \
      -e 's/%3D/=/g' \
      -e 's/%40/@/g' \
      -e 's/%2D/-/g' \
      -e 's/%28/(/g' \
      -e 's/%29/)/g' \
      -e 's/%25/%/g' \
      -e 's/%5B/[/g' \
      -e 's/%5D/]/g' \
      -e 's/%7B/{/g' \
      -e 's/%7D/}/g' \
      -e 's/%7E/~/g' \
      -e 's/%2A/*/g' \
      -e 's/%2E/\./g' \
      -e 's/%5C/\\/g' |
  sed 's|/ *|/|g' )

	# Save recent files to RECENT_FILES_LIST
	echo "$RECENT_FILES" > "$RECENT_FILES_LIST"

	# Get the last few recent files (the most recent 40 files)
	RECENT_FILES_LAST_40=$(tail -n 40 "$RECENT_FILES_LIST")

	# Save the recent 40 files to RECENT_FILES_LIST
	echo "$RECENT_FILES_LAST_40" > "$RECENT_FILES_LIST"

	# Place recent files list to an array 
	mapfile -t RECENT_FILES_ARRAY < "$RECENT_FILES_LIST"

	# Check if the array is empty
	if [ ${#RECENT_FILES_ARRAY[@]} -eq 0 ]; then
		notify-send "No recent files found." &
		sleep 5  # Pause for a moment before the next loop iteration
		continue
	fi

	# Add line numbers to the recent files and display
	nl "$RECENT_FILES_LIST" > "$TAIL_LIST"
	cat "$TAIL_LIST"

	# Prompt the user to select a file
	echo "Please provide the sequence number of the accessed file: "
	read -r SEQUENCE_NUM

	# Validate user input
	if [[ ! "$SEQUENCE_NUM" =~ ^[0-9]+$ ]] || [[ "$SEQUENCE_NUM" -lt 1 ]] || [[ "$SEQUENCE_NUM" -gt "${#RECENT_FILES_ARRAY[@]}" ]]; then
		notify-send "Invalid input. Please enter a valid sequence number." &
		continue
	fi

	# Get the selected file 
	SELECTED_FILE="${RECENT_FILES_ARRAY[SEQUENCE_NUM - 1]}"

	# Check if selected file is a directory or file
	if [[ -d "$SELECTED_FILE" ]]; then
		# Open the folder with a file manager
		pcmanfm-qt "$SELECTED_FILE" &
	elif [[ -f "$SELECTED_FILE" ]]; then
		# Open the file with the preferred application
		xdg-open "$SELECTED_FILE" &
	else
		notify-send "Path does not exist: $SELECTED_FILE" &
	fi
done

