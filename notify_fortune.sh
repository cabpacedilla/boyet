#!/usr/bin/env bash
export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
while true; do

# Alert the random quote
# notify-send -u critical --app-name "Fortune:" "$(fortune)"
kdialog --title "Fortune" --msgbox "$(fortune)" &

# Sleep in random seconds
sleep "$(shuf -i1200-1500 -n1)"

done
