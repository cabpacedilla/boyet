#!/bin/bash
while true; do

# Alert the random quote
# notify-send -u critical --app-name "Fortune:" "$(fortune)"
kdialog --title "Fortune" --msgbox "$(fortune)" &

# Sleep in random time
sleep "$(shuf -i1200-1500 -n1)"

done
