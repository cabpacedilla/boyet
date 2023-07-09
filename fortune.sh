#!/bin/bash
while true; do

# Find fortune file randomly
FORTUNEFILE=$(find ~/Documents/claive/fortune | shuf -n 1 &)

# Put the quotes in an array by using '%' delimiter in the quotes to separate the items 
declare -a ARR=(); readarray -td% arr < "$FORTUNEFILE" 

# Get a quote randomly
RAND=${arr[$RANDOM % ${#arr[@]}]}

MESSAGE=${RAND#"${RAND%%[![:space:]]*}"}

# Alert the random quote
notify-send -u critical "$MESSAGE"

# Sleep in random time
sleep $(( $RANDOM % 900 + 600 ))

done
