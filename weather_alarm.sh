#!/usr/bin/env bash

API_KEY="98ddb8a158f24a1596882148251309"

WARNINGS=()
EMOJIS=()

# Control which data to show in normal section
SHOW_TEMP=true
SHOW_HUMIDITY=true
SHOW_WIND=true
SHOW_PRECIP=true
SHOW_UV=true

# Detect notification command
get_notifier() {
    if command -v kdialog &>/dev/null; then
        NOTIFIER="kdialog"
    elif command -v notify-send &>/dev/null; then
        NOTIFIER="notify-send"
    else
        echo "No supported notification command found (kdialog or notify-send)."
        exit 1
    fi
}

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

    TEMP_C=$(jq -r '.current.temp_c' <<< "$DATA")
    HUMIDITY=$(jq -r '.current.humidity' <<< "$DATA")
    WIND_KPH=$(jq -r '.current.wind_kph' <<< "$DATA")
    PRECIP_MM=$(jq -r '.current.precip_mm' <<< "$DATA")
    UV=$(jq -r '.current.uv' <<< "$DATA")

    echo "Weather fetched for $CITY: Temp=${TEMP_C}°C, Humidity=${HUMIDITY}%, Wind=${WIND_KPH} kph, Rain=${PRECIP_MM} mm, UV=${UV}"
}

check_conditions() {
    WARNINGS=()
    EMOJIS=()

    # Temperature alert
    if (( $(echo "$TEMP_C > 34" | bc -l) )); then
        WARNINGS+=("🔥 High temperature (${TEMP_C}°C) - Stay hydrated!")
        EMOJIS+=("🔥")
        SHOW_TEMP=false
    else
        SHOW_TEMP=true
    fi

    # Humidity alert
    if (( HUMIDITY > 80 )); then
        WARNINGS+=("💧 High humidity (${HUMIDITY}%) - Stay in airy place.")
        EMOJIS+=("💧")
        SHOW_HUMIDITY=false
    else
        SHOW_HUMIDITY=true
    fi

    # Precipitation alert
    if (( $(echo "$PRECIP_MM > 0" | bc -l) )); then
        if (( $(echo "$PRECIP_MM <= 2.5" | bc -l) )); then
            WARNINGS+=("🌦 Light rain (${PRECIP_MM} mm) - Use umbrella.")
            EMOJIS+=("🌦")
        else
            WARNINGS+=("🌩 Heavy rain (${PRECIP_MM} mm) - Flooding risk!")
            EMOJIS+=("🌩")
        fi
        SHOW_PRECIP=false
    else
        SHOW_PRECIP=true
    fi

    # UV alert
    if (( $(echo "$UV >= 3 && $UV < 6" | bc -l) )); then
        WARNINGS+=("🟡 Moderate UV ($UV) - Wear sun protection.")
        EMOJIS+=("🟡")
        SHOW_UV=false
    elif (( $(echo "$UV >= 6 && $UV < 8" | bc -l) )); then
        WARNINGS+=("🟠 High UV ($UV) - Apply sunscreen!")
        EMOJIS+=("🟠")
        SHOW_UV=false
    elif (( $(echo "$UV >= 8" | bc -l) )); then
        WARNINGS+=("🔴 Very high UV ($UV) - Avoid direct sun!")
        EMOJIS+=("🔴")
        SHOW_UV=false
    else
        SHOW_UV=false
    fi
}

send_notifications() {
    if (( ${#WARNINGS[@]} > 0 )); then
        for warning in "${WARNINGS[@]}"; do
            MESSAGE+="• $warning"$'\n'
        done
        MESSAGE+=$'\n'
    fi

    $SHOW_TEMP && MESSAGE+="• Temp: ${TEMP_C}°C\n"
    $SHOW_HUMIDITY && MESSAGE+="• Hum: ${HUMIDITY}%\n"
    $SHOW_WIND && MESSAGE+="• Wind: ${WIND_KPH} kph\n"
    $SHOW_PRECIP && MESSAGE+="• Rain: ${PRECIP_MM} mm\n"
    $SHOW_UV && MESSAGE+="• UV: ${UV}\n"

    TITLE="⛅ Weather $CITY"

    case "$NOTIFIER" in
        kdialog)
            # kdialog display on notification area
            kdialog --passivepopup "$MESSAGE" --title "$TITLE"
            ;;
        notify-send)
            # GNOME-style passive notification (timeout 15s)
            notify-send "$TITLE" "$MESSAGE" -u critical -t 15000
            ;;
    esac
}

main() {
    get_location
    get_weather
    check_conditions
    send_notifications
}

get_notifier

# Loop every 15 minutes
while true; do
    main
    sleep 900
done
