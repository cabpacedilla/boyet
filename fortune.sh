#!/bin/bash
while true; do

declare -a FORTARR=();
declare -a FILEARR=();

select_file2array(){
	# Find fortune file randomly
	FORTUNEFILE=$(find ~/Documents/claive/fortune -type f | shuf -n 1)
	
	FILEARR+=("$FORTUNEFILE")
	
	# Put the quotes in an array by using '%' delimiter in the quotes to separate the items 
	readarray -d %'\n' -t FORTARR < "$FORTUNEFILE" 
}

select_random(){
    printf "%s\0" "$@" | shuf -z -n 1 | tr -d '\0'
}

select_file2array
if echo "${FILEARR[@]}" | grep "$FORTUNEFILE"; then
	:
else
	select_file2array
fi

while [ "${FORTUNEFILE}" = "${OLDFILE}" ]; do
		select_file2array
done

# Get a quote randomly
#RANDFORTUNE=${ARR[$RANDOM % ${#ARR[@]}]}
RANDFORTUNE=$(select_random "${FORTARR[@]}")

if [ -z "${RANDFORTUNE}" ]; then
	continue
fi

while [ "${RANDFORTUNE}" = "${OLDFORTUNE}" ]; do	
	RANDFORTUNE=$(select_random "${FORTARR[@]}")
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
