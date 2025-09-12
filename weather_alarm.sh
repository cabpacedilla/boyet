#!/usr/bin/bash

# Weather Warning Script with Collation (KDE version)
# Written by Claive Alvin P. Acedilla + merged improvements
# Features:
#  - Auto-detect location via IP + reverse geocoding
#  - Falls back to manual prompt if needed
#  - Logs location and weather fetch attempts
#  - Runs every 15 minutes in loop
#  - Weather warnings (Humidity, Heat, Rain, UV) with categories
#  - Collates warnings if more than one
#  - Uses KDE kdialog passive popups instead of notify-send

LOG_DIR="$HOME/scriptlogs"
mkdir -p "$LOG_DIR"
LOCATION_FILE="$LOG_DIR/current_location.txt"
LOCATION_LOG="$LOG_DIR/location_log.txt"
WEATHER_LOG="$LOG_DIR/weather_fetch_log.txt"

# 🔍 Detect location
get_location() {
    LAT=$(curl -s ipinfo.io/loc | cut -d, -f1)
    LON=$(curl -s ipinfo.io/loc | cut -d, -f2)
    if [[ -n "$LAT" && -n "$LON" ]]; then
        LOCATION=$(curl -s "https://nominatim.openstreetmap.org/reverse?lat=$LAT&lon=$LON&format=json" \
                   | jq -r '.address.city // .address.town // .address.village // .address.state')
        if [[ -n "$LOCATION" && "$LOCATION" != "null" ]]; then
            echo "Location resolved via ipinfo + nominatim: $LOCATION" >> "$LOCATION_LOG"
            echo "$LOCATION" > "$LOCATION_FILE"
            return
        fi
    fi

    # fallback ip-api
    LOCATION=$(curl -s ip-api.com/json | jq -r '.city')
    if [[ -n "$LOCATION" && "$LOCATION" != "null" ]]; then
        echo "Location resolved via ip-api: $LOCATION" >> "$LOCATION_LOG"
        echo "$LOCATION" > "$LOCATION_FILE"
        return
    fi

    # fallback ipinfo city
    LOCATION=$(curl -s ipinfo.io/city)
    if [[ -n "$LOCATION" && "$LOCATION" != "null" ]]; then
        echo "Location resolved via ipinfo city: $LOCATION" >> "$LOCATION_LOG"
        echo "$LOCATION" > "$LOCATION_FILE"
        return
    fi

    # cached
    if [[ -f "$LOCATION_FILE" ]]; then
        LOCATION=$(cat "$LOCATION_FILE")
        echo "Using cached location: $LOCATION" >> "$LOCATION_LOG"
        return
    fi

    # user prompt
    if command -v kdialog >/dev/null 2>&1; then
        LOCATION=$(kdialog --inputbox "Enter your location:")
    else
        read -rp "Enter your location: " LOCATION
    fi
    echo "User entered location: $LOCATION" >> "$LOCATION_LOG"
    echo "$LOCATION" > "$LOCATION_FILE"
}

# 🔔 Notification helper (KDE popup)
send_notification() {
    local title="$1"
    local message="$2"
    kdialog --passivepopup "$message" 10 --title "$title"
}

# 🌤 Weather fetch
get_weather() {
    LOCATION=$(cat "$LOCATION_FILE" 2>/dev/null || echo "Cebu")
    LOCATION_QUERY=$(echo "$LOCATION" | tr ' ' '_')
    DATA=$(curl -s "wttr.in/$LOCATION_QUERY?format=%t,%h,%p,%w,%U")
    TEMP=$(echo "$DATA" | cut -d, -f1 | tr -d '+°C')
    HUMIDITY=$(echo "$DATA" | cut -d, -f2 | tr -d '%')
    PRECIP=$(echo "$DATA" | cut -d, -f3 | tr -d 'mm')
    WIND=$(echo "$DATA" | cut -d, -f4)
    UV=$(echo "$DATA" | cut -d, -f5)
    echo "Weather fetched for $LOCATION: $DATA" >> "$WEATHER_LOG"
}

# 📦 Collation arrays
WARNINGS=()
EMOJIS=()

add_warning() {
    local emoji="$1"
    local text="$2"
    WARNINGS+=("$text")
    EMOJIS+=("$emoji")
}

send_collated_warnings() {
    local count=${#WARNINGS[@]}
    if [[ $count -eq 1 ]]; then
        send_notification "${EMOJIS[0]} Weather Warning" "${WARNINGS[0]}"
    elif [[ $count -gt 1 ]]; then
        local now=$(date +"%I:%M %p")
        local joined_emojis=$(printf "%s" "${EMOJIS[@]}" | tr -d '\n')
        local message="Weather warnings for $LOCATION:\n"
        for i in "${!WARNINGS[@]}"; do
            message+="\n- ${WARNINGS[$i]}"
        done
        send_notification "$joined_emojis Weather Alert: $now" "$message"
    fi
    WARNINGS=()
    EMOJIS=()
}


# ⚠️ Weather checks
check_conditions() {
    # Humidity
    if (( HUMIDITY > 80 )); then
        add_warning "💧" "Very humid (${HUMIDITY}%) - Stay in an airy place."
    fi
    # Heat
    if (( TEMP > 34 )); then
        add_warning "🔥" "Very hot (${TEMP}°C) - Stay in a cooler place."
    fi
    # Rain
    if (( $(echo "$PRECIP > 0" | bc -l) )); then
        if (( $(echo "$PRECIP < 2" | bc -l) )); then
            add_warning "🌦️" "Light rain (${PRECIP}mm) - Use an umbrella."
        elif (( $(echo "$PRECIP < 10" | bc -l) )); then
            add_warning "🌧️" "Moderate rain (${PRECIP}mm) - Wear raincoat."
        elif (( $(echo "$PRECIP < 50" | bc -l) )); then
            add_warning "⛈️" "Heavy rain (${PRECIP}mm) - Stay safe indoors."
        else
            add_warning "🌪️" "Violent rain (${PRECIP}mm) - Extreme caution!"
        fi
    fi
    # UV
    if (( UV > 2 )); then
        if (( UV <= 5 )); then
            add_warning "😎" "Moderate UV ($UV) - Use sunscreen."
        elif (( UV <= 7 )); then
            add_warning "🧴" "High UV ($UV) - Wear sunglasses, sunscreen."
        elif (( UV <= 10 )); then
            add_warning "🧢" "Very high UV ($UV) - Avoid direct sun."
        else
            add_warning "☢️" "Extreme UV ($UV) - Stay indoors if possible."
        fi
    fi
    send_collated_warnings
}

# 🔁 Loop
while true; do
    get_location
    get_weather
    check_conditions
    sleep 15m
done
