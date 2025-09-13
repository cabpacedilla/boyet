#!/usr/bin/env bash

API_KEY="98ddb8a158f24a1596882148251309"
WARNINGS=()
EMOJIS=()

get_location() {
    # Get latitude and longitude from ipinfo.io
    LOC=$(curl -s ipinfo.io/loc)  # returns "lat,lon"
    LAT=$(echo "$LOC" | cut -d, -f1)
    LON=$(echo "$LOC" | cut -d, -f2)

    # Reverse geocode to get city name only
    CITY=$(curl -s "https://nominatim.openstreetmap.org/reverse?lat=$LAT&lon=$LON&format=json" \
        | jq -r '.address.city // .address.town // .address.village // .address.hamlet // "Unknown"')

    echo "Location detected: $CITY ($LAT,$LON)"
}

get_weather() {
    DATA=$(curl -s "http://api.weatherapi.com/v1/current.json?key=$API_KEY&q=${LAT},${LON}&aqi=no")

    WEATHER=$(echo "$DATA" | jq -r '.current.condition.text')
    TEMP_C=$(echo "$DATA" | jq -r '.current.temp_c')
    HUMIDITY=$(echo "$DATA" | jq -r '.current.humidity')
    WIND_KPH=$(echo "$DATA" | jq -r '.current.wind_kph')
    PRECIP_MM=$(echo "$DATA" | jq -r '.current.precip_mm')
    UV=$(echo "$DATA" | jq -r '.current.uv')

    echo "Weather fetched for $CITY: $WEATHER, Temp=${TEMP_C}°C, Humidity=$HUMIDITY%, Wind=${WIND_KPH}kph, Precip=${PRECIP_MM}mm, UV=$UV"
}

check_conditions() {
    WARNINGS=()
    EMOJIS=()

    # Temperature warnings
    if (( $(echo "$TEMP_C > 34" | bc -l) )); then
        WARNINGS+=("High temperature (${TEMP_C}°C) - Stay cool.")
        EMOJIS+=("🔥")
    fi

    # Humidity warnings
    if (( $(echo "$HUMIDITY > 80" | bc -l) )); then
        WARNINGS+=("High humidity ($HUMIDITY%) - Stay in airy place.")
        EMOJIS+=("💧")
    fi

    # Wind warnings
    if (( $(echo "$WIND_KPH > 40" | bc -l) )); then
        WARNINGS+=("Strong wind (${WIND_KPH}kph) - Stay inside.")
        EMOJIS+=("🌬️")
    fi

    # Rain warnings
    if (( $(echo "$PRECIP_MM > 0" | bc -l) )); then
        if (( $(echo "$PRECIP_MM <= 2.5" | bc -l) )); then
            WARNINGS+=("Light rain (${PRECIP_MM} mm) - Use umbrella.")
            EMOJIS+=("🌦")
        elif (( $(echo "$PRECIP_MM <= 10" | bc -l) )); then
            WARNINGS+=("Moderate rain (${PRECIP_MM} mm) - Wear raincoat.")
            EMOJIS+=("🌧")
        else
            WARNINGS+=("Heavy rain (${PRECIP_MM} mm) - Stay safe indoors.")
            EMOJIS+=("🌩")
        fi
    fi

    # UV warnings
    if (( $(echo "$UV >= 3 && $UV < 6" | bc -l) )); then
        WARNINGS+=("Moderate UV ($UV) - Use sunscreen.")
        EMOJIS+=("🧴")
    elif (( $(echo "$UV >= 6 && $UV < 8" | bc -l) )); then
        WARNINGS+=("High UV ($UV) - Sunscreen & sunglasses recommended.")
        EMOJIS+=("🧴😎")
    elif (( $(echo "$UV >= 8 && $UV < 11" | bc -l) )); then
        WARNINGS+=("Very High UV ($UV) - Stay in shade & protect skin.")
        EMOJIS+=("🧴😎🏠")
    elif (( $(echo "$UV >= 11" | bc -l) )); then
        WARNINGS+=("Extreme UV ($UV) - Stay indoors & fully protect yourself.")
        EMOJIS+=("🧴😎🏠")
    fi
}

send_notifications() {
    local count=${#WARNINGS[@]}
    if (( count == 0 )); then
        echo "No warnings to send."
        return
    fi

    # Join emojis for title
    local joined_emojis=$(printf "%s" "${EMOJIS[@]}" | tr -d '\n')

    # Build collated message with bullets
    local message="Weather warnings for $CITY:"
    for w in "${WARNINGS[@]}"; do
        message+="\n• $w"
    done

    # Send a single passive popup with all warnings
    kdialog --passivepopup "$(echo -e "$message")" 15 --title "$joined_emojis Weather Alert"
}

main() {
    get_location
    get_weather
    check_conditions
    send_notifications
}

main
