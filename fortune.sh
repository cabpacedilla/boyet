#!/bin/bash
while true; do

select_random() {
    printf "%s\0" "$@" | shuf -z -n1 | tr -d '\0'
}

# Find fortune file randomly
FORTUNEFILE=$(find ~/Documents/claive/fortune | shuf -n 1)

# Put the quotes in an array by using '%' delimiter in the quotes to separate the items 
declare -a ARR=(); 
readarray -td% ARR < "$FORTUNEFILE" 

# Get a quote randomly
#RANDFORTUNE=${ARR[$RANDOM % ${#ARR[@]}]}
RANDFORTUNE=$(select_random "${ARR[@]}")

if [ -z "${RANDFORTUNE}" ]; then
	continue
fi

# Remove 
MESSAGE=${RANDFORTUNE#"${RANDFORTUNE%%[![:space:]]*}"}

# Alert the random quote
notify-send -u critical "$MESSAGE"

# Sleep in random time
sleep $(shuf -i1200-1500 -n1)

done
