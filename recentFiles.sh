#!/usr/bin/env bash
# This script is used to monitor and access recently used files
# This script was assembled written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# June 2024

#!/usr/bin/env bash

# Define file paths
RECENT_FILES_LIST=~/scriptlogs/recentFiles.txt
TAIL_LIST=~/scriptlogs/reverseRecent.txt
RECENTLY_XBEL_FILE=~/.local/share/recently-used.xbel

# Infinite loop to continuously check recent files
while true; do

  # Extract recent file paths from the recently-used.xbel file
  RECENT_FILES=$(awk -F 'file://|" ' '/file:\/\// {print $2}' "$RECENTLY_XBEL_FILE" | sed 's/%20/ /g')
  
  # Save recent files to RECENT_FILES_LIST
  echo "$RECENT_FILES" > "$RECENT_FILES_LIST"

  # Get the last few recent files (the most recent 40 files)
  RECENT_FILES_LAST_40=$(tail -n 40 "$RECENT_FILES_LIST")

  # Save the recent 40 files to RECENT_FILES_LIST
  echo "$RECENT_FILES_LAST_40" > "$RECENT_FILES_LIST"

  # Initialize an array to hold recent files
  mapfile -t RECENT_FILES_ARRAY < "$RECENT_FILES_LIST"

  # Add line numbers to the recent files
  echo "$RECENT_FILES_LAST_40" | nl > "$TAIL_LIST"
  RECENT_FILES_NUMBERED=$(cat "$TAIL_LIST")
  echo "$RECENT_FILES_NUMBERED"

  # Prompt the user to select a file
  echo "Please provide the sequence number of the accessed file: "
  read -r SEQUENCE_NUM

  # Validate user input
  if [[ ! "$SEQUENCE_NUM" =~ ^[0-9]+$ ]] || [[ "$SEQUENCE_NUM" -lt 1 ]] || [[ "$SEQUENCE_NUM" -gt "${#RECENT_FILES_ARRAY[@]}" ]]; then
    notify-send "Invalid input. Please enter a valid sequence number." &
    continue
  fi

  # Get the selected file and clean up any escaped characters
  SELECTED_FILE="${RECENT_FILES_ARRAY[SEQUENCE_NUM - 1]}"
  SELECTED_FILE=$(echo "$SELECTED_FILE" | sed 's/%20/ /g; s/%2520/ /g' | xargs)

  # Check if the file exists before attempting to open it
  if [ -f "$SELECTED_FILE" ]; then
    # Open the selected file
    xdg-open "$SELECTED_FILE" &
  else
    notify-send "File does not exist: $SELECTED_FILE" &
  fi

done
