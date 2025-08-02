#!/bin/bash
while true; do

# Alert the random quote
notify-send -u critical --app-name "Fortune:" "$(fortune)"
s
# Sleep in random seconds
sleep "$(shuf -i1200-1500 -n1)"

done
