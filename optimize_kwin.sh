#!/usr/bin/env bash

# Wait a few seconds to ensure kwin is fully initialized
sleep 5

# Find the current PID of kwin_wayland
KWIN_PID=$(pidof kwin_wayland)

if [ -n "$KWIN_PID" ]; then
    # Apply CPU Priority (Nice)
    sudo renice -n -20 -p "$KWIN_PID"
    # Apply I/O Priority (Real-Time)
    sudo ionice -c 1 -n 0 -p "$KWIN_PID"
    # Apply Scheduling Priority (Real-Time Round Robin)
    sudo chrt -r -p 99 "$KWIN_PID"
    
    echo "KWin (PID: $KWIN_PID) optimized for Real-Time performance."
else
    echo "KWin process not found."
fi
