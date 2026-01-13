#!/usr/bin/env bash

# Ensure the log directory exists
mkdir -p "$HOME/scriptlogs"

while true; do
  CURRENT_DAY=$(date +%d)
  LOGFILE="$HOME/scriptlogs/btrfs-scrub-$(date +%Y-%m-%d).log"

  # Check if it is NOT the 15th
  if [ "$CURRENT_DAY" != "15" ]; then
    echo "Current day is $CURRENT_DAY. Not the 15th. Skipping scrub and sleeping 24h." >> "$LOGFILE"
    sleep 86400
    continue
  fi

  # --- This part only runs on the 15th ---
  echo -e "\nStarting Btrfs scrub on / at $(date)" | tee -a "$LOGFILE"
  notify-send "✅ Btrfs Scrub" "Starting Btrfs scrub on / at $(date)"
  
  # Note: sudo might prompt for a password if run in a terminal, 
  # but will fail in a background process unless configured in sudoers.
  sudo btrfs scrub start -Bd / >> "$LOGFILE" 2>&1
  
  echo "Btrfs scrub completed at $(date)" | tee -a "$LOGFILE"
  notify-send "✅ Btrfs Scrub" "Btrfs scrub completed at $(date)"

  echo -e "\nBtrfs filesystem usage at $(date)" | tee -a "$LOGFILE"
  sudo btrfs filesystem usage / | tee -a "$LOGFILE"

  # Sleep for 24 hours to avoid re-running the scrub on the same day
  sleep 86400
done
