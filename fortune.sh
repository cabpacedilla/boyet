#!/bin/bash
while true; do

declare -a ARR=();

select_file_to_array(){
	# Find fortune file randomly
	FORTUNEFILE=$(find ~/Documents/claive/fortune -type f | shuf -n 1)
	
	# Put the quotes in an array by using '%' delimiter in the quotes to separate the items 
	readarray -td% ARR < "$FORTUNEFILE" 
}

select_random(){
    printf "%s\0" "$@" | shuf -z -n1 | tr -d '\0'
}

select_file_to_array
while [ "${FORTUNEFILE}" = "${OLDFILE}" ]; do
		select_file2array
done

# Get a quote randomly
#RANDFORTUNE=${ARR[$RANDOM % ${#ARR[@]}]}
RANDFORTUNE=$(select_random "${ARR[@]}")

if [ -z "${RANDFORTUNE}" ]; then
	continue
fi

while [ "${RANDFORTUNE}" = "${OLDFORTUNE}" ]; do	
	RANDFORTUNE=$(select_random "${ARR[@]}")
done
	
# Remove 
MESSAGE=${RANDFORTUNE#"${RANDFORTUNE%%[![:space:]]*}"}

# Alert the random quote
notify-send -u critical --app-name "Fortune:" "$MESSAGE"

OLDFORTUNE="$RANDFORTUNE"

OLDFILE="$FORTUNEFILE"

# Sleep in random time
sleep "$(shuf -i1200-1500 -n1)"

done
