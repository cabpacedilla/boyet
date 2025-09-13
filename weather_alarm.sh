#!/usr/bin/env bash

API_KEY="98ddb8a158f24a1596882148251309"

WARNINGS=()
EMOJIS=()

get_location() {
    LOC=$(curl -s ipinfo.io/loc)
    LAT=$(echo "$LOC" | cut -d, -f1)
    LON=$(echo "$LOC" | cut -d, -f2)

    CITY=$(curl -s "https://nominatim.openstreetmap.org/reverse?lat=$LAT&lon=$LON&format=json" \
           | jq -r '.address.city // .address.town // .address.village // .address.hamlet // "Unknown"')

    echo "Location detected: $CITY ($LAT,$LON)"
}

get_weather() {
    DATA=$(curl -s "http://api.weatherapi.com/v1/current.json?key=$API_KEY&q=$LAT,$LON&aqi=no")

    # Extract fields individually to avoid splitting issues
    WEATHER=$(jq -r '.current.condition.text' <<< "$DATA")
    TEMP_C=$(jq -r '.current.temp_c' <<< "$DATA")
    HUMIDITY=$(jq -r '.current.humidity' <<< "$DATA")
    WIND_KPH=$(jq -r '.current.wind_kph' <<< "$DATA")
    PRECIP_MM=$(jq -r '.current.precip_mm' <<< "$DATA")
    UV=$(jq -r '.current.uv' <<< "$DATA")

    echo "Weather fetched for $CITY: $WEATHER, Temp=${TEMP_C}°C, Humidity=${HUMIDITY}%, Wind=${WIND_KPH}kph, Precip=${PRECIP_MM}mm, UV=$UV"
}

check_conditions() {
    WARNINGS=()
    EMOJIS=()

    (( $(echo "$TEMP_C > 34" | bc -l) )) && WARNINGS+=("🔥 High temperature (${TEMP_C}°C) - Stay hydrated!") && EMOJIS+=("🔥")
    (( HUMIDITY > 80 )) && WARNINGS+=("💧 High humidity (${HUMIDITY}%) - Stay in airy place.") && EMOJIS+=("💧")

    if (( $(echo "$PRECIP_MM > 0" | bc -l) )); then
        if (( $(echo "$PRECIP_MM <= 2.5" | bc -l) )); then
            WARNINGS+=("🌦 Light rain (${PRECIP_MM} mm) - Use umbrella.")
            EMOJIS+=("🌦")
        else
            WARNINGS+=("🌩 Heavy rain (${PRECIP_MM} mm) - Flooding risk!")
            EMOJIS+=("🌩")
        fi
    fi

    if (( $(echo "$UV >= 3 && $UV < 6" | bc -l) )); then
        WARNINGS+=("🟡 Moderate UV ($UV) - Wear sun protection.")
        EMOJIS+=("🟡")
    elif (( $(echo "$UV >= 6 && $UV < 8" | bc -l) )); then
        WARNINGS+=("🟠 High UV ($UV) - Apply sunscreen!")
        EMOJIS+=("🟠")
    elif (( $(echo "$UV >= 8" | bc -l) )); then
        WARNINGS+=("🔴 Very high UV ($UV) - Avoid direct sun!")
        EMOJIS+=("🔴")
    fi
}

send_notifications() {
    local count=${#WARNINGS[@]}
    if (( count == 0 )); then return; fi

    MESSAGE=""
    for warning in "${WARNINGS[@]}"; do
        MESSAGE+="• $warning"$'\n'
    done

    TITLE="${EMOJIS[0]:-🌦} Weather $CITY"
    kdialog --passivepopup "$MESSAGE" 10 --title "$TITLE"
}

main() {
    get_location
    get_weather
    check_conditions
    send_notifications
}

# Loop every 15 minutes
while true; do
    main
    sleep 900  # 15 minutes
done
