#!/usr/bin/env bash

while true; do
  # Run only on the 15th day of the month
  if [ "$(date +%d)" != "15" ]; then
    sleep 86400
    continue
  fi

  LOGFILE="$HOME/scriptlogs/btrfs-scrub-$(date +%Y-%m-%d).log"

  echo -e "\nStarting Btrfs scrub on / at $(date)" | tee -a "$LOGFILE"
  notify-send "✅ Btrfs Scrub" "Starting Btrfs scrub on / at $(date)"
  sudo btrfs scrub start -Bd / >> "$LOGFILE" 2>&1
  echo "Btrfs scrub completed at $(date)" | tee -a "$LOGFILE"
  notify-send "✅ Btrfs Scrub" "Btrfs scrub completed at $(date)"

  echo -e "\nBtrfs filesystem usage at $(date)" | tee -a "$LOGFILE"
  sudo btrfs filesystem usage / | tee -a "$LOGFILE"


  # Sleep for 24 hours to avoid re-running the scrub on the same day
  sleep 86400
done
