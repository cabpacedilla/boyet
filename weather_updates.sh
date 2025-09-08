#!/bin/bash
# weather_updates.sh
# Weather Alert Script
# Fetches weather info from wttr.in, checks conditions, and sends notifications.
# First run asks for location and saves it in config.
# Subsequent runs use saved location automatically.

set -euo pipefail

readonly SCRIPT_NAME="Weather Alert"

# Config and cache paths
readonly CONFIG_DIR="$HOME/.config/weather-alert"
readonly CONFIG_FILE="$CONFIG_DIR/config.conf"
readonly CACHE_DIR="$HOME/.cache/weather-alert"
readonly LOG_FILE="$CONFIG_DIR/weather-alert.log"
readonly WEATHER_CACHE="$CACHE_DIR/current_weather.json"

# Thresholds
HUMIDITY_HIGH=85
TEMP_HIGH=33
WIND_STRONG=50
RAIN_LIGHT=0.1
RAIN_MODERATE=2.5
RAIN_HEAVY=7.6
RAIN_VIOLENT=50
UV_LOW=2
UV_MODERATE=6
UV_HIGH=8
UV_VERY_HIGH=11

# Curl settings
readonly CURL_TIMEOUT=15
readonly MAX_RETRIES=3

# Default values
LOCATION=""
INTERVAL=600

# Data holders
declare -A WEATHER_DATA
declare -A LAST_ALERTS=(["summary"]='')

mkdir -p "$CONFIG_DIR" "$CACHE_DIR"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"
}

notify() {
    local msg="$1"
    notify-send -u normal "$SCRIPT_NAME" "$msg"
    log "$msg"
}

# ---- Clean final load_config ----
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        # First run, no config yet
        if [[ -t 0 ]]; then
            # Interactive terminal → ask user
            read -rp "Enter your city/location: " LOCATION
            LOCATION=$(echo "$LOCATION" | sed 's/[[:space:]]*$//; s/[?]$//')

            # Save config
            {
                echo "LOCATION=\"$LOCATION\""
                echo "INTERVAL=$INTERVAL"
            } > "$CONFIG_FILE"

            log "Saved configuration for $LOCATION"
        else
            # Non-interactive, no config available
            log "ERROR: No config file and cannot prompt for location (non-interactive run)."
            exit 1
        fi
    else
        # Config already exists → load
        source "$CONFIG_FILE"
        LOCATION=$(echo "$LOCATION" | sed 's/[[:space:]]*$//; s/[?]$//')
    fi
}


# --------------------------------

fetch_weather() {
    local retries=0
    local url="https://wttr.in/${LOCATION}?format=j1"

    while (( retries < MAX_RETRIES )); do
        if curl -s --connect-timeout "$CURL_TIMEOUT" --max-time "$CURL_TIMEOUT" \
            "$url" -o "$WEATHER_CACHE"; then
            return 0
        fi
        ((retries++))
        sleep 2
    done
    log "Failed to fetch weather after $MAX_RETRIES retries"
    return 1
}

parse_weather() {
    [[ -s "$WEATHER_CACHE" ]] || return 1

    WEATHER_DATA[temperature]=$(jq -r '.current_condition[0].temp_C' "$WEATHER_CACHE")
    WEATHER_DATA[humidity]=$(jq -r '.current_condition[0].humidity' "$WEATHER_CACHE")
    WEATHER_DATA[wind]=$(jq -r '.current_condition[0].windspeedKmph' "$WEATHER_CACHE")
    WEATHER_DATA[precip]=$(jq -r '.current_condition[0].precipMM' "$WEATHER_CACHE")
    WEATHER_DATA[uv]=$(jq -r '.current_condition[0].uvIndex' "$WEATHER_CACHE")
    WEATHER_DATA[condition]=$(jq -r '.current_condition[0].weatherDesc[0].value' "$WEATHER_CACHE")
}

check_alerts() {
    local msg=""

    (( WEATHER_DATA[temperature] >= TEMP_HIGH )) && msg+="🔥 High temp: ${WEATHER_DATA[temperature]}°C\n"
    (( WEATHER_DATA[humidity] >= HUMIDITY_HIGH )) && msg+="💧 High humidity: ${WEATHER_DATA[humidity]}%\n"
    (( WEATHER_DATA[wind] >= WIND_STRONG )) && msg+="💨 Strong wind: ${WEATHER_DATA[wind]} km/h\n"

    if (( $(echo "${WEATHER_DATA[precip]} >= $RAIN_HEAVY" | bc -l) )); then
        msg+="🌧️ Heavy rain: ${WEATHER_DATA[precip]} mm\n"
    elif (( $(echo "${WEATHER_DATA[precip]} >= $RAIN_MODERATE" | bc -l) )); then
        msg+="🌦️ Moderate rain: ${WEATHER_DATA[precip]} mm\n"
    elif (( $(echo "${WEATHER_DATA[precip]} >= $RAIN_LIGHT" | bc -l) )); then
        msg+="🌦️ Light rain: ${WEATHER_DATA[precip]} mm\n"
    fi

    (( WEATHER_DATA[uv] >= UV_HIGH )) && msg+="☀️ High UV index: ${WEATHER_DATA[uv]}\n"

    if [[ -n "$msg" && "$msg" != "${LAST_ALERTS[summary]}" ]]; then
        notify "$msg"
        LAST_ALERTS[summary]="$msg"
    fi
}

main() {
    load_config
    log "Starting Weather Alert for $LOCATION (interval ${INTERVAL}s)"
    while true; do
        if fetch_weather; then
            parse_weather
            check_alerts
        fi
        sleep "$INTERVAL"
    done
}

main
