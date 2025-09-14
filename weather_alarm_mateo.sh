#!/usr/bin/env bash
# Weather Alarm Script (Open-Meteo)
# - Alerts (current dangerous conditions only, with advice)
# - Current (safe values only, no duplication from alerts)
# - Forecast (hourly breakdown for next 3h + today's min/max + peak UV, with advice)

API="https://api.open-meteo.com/v1/forecast"
INTERVAL=900  # 15 minutes

# ------------------------
# Weather code → Emoji + Text
# ------------------------
weather_code_to_text() {
    case "$1" in
        0) echo "☀️ Clear sky" ;;
        1) echo "🌤 Mainly clear" ;;
        2) echo "⛅ Partly cloudy" ;;
        3) echo "☁️ Overcast" ;;
        45|48) echo "🌫 Fog" ;;
        51|53|55) echo "🌦 Drizzle" ;;
        61|63|65) echo "🌧 Rain" ;;
        71|73|75) echo "❄️ Snow fall" ;;
        77) echo "🌨 Snow grains" ;;
        80|81|82) echo "🌦 Showers" ;;
        85|86) echo "❄️ Snow showers" ;;
        95) echo "⛈ Thunderstorm" ;;
        96|99) echo "⛈ Thunderstorm w/ hail" ;;
        *) echo "❓ Unknown" ;;
    esac
}

# ------------------------
# Feels-like calculation
# ------------------------
calculate_feels_like() {
    local T="$1" H="$2" W="$3"
    local HI="$T"

    if (( $(echo "$T >= 27 && $H > 40" | bc -l) )); then
        HI=$(echo "
            scale=4
            T=$T; R=$H
            -8.784695 + 1.61139411*T + 2.338549*R - 0.14611605*T*R \
            - 0.012308094*T*T - 0.016424828*R*R \
            + 0.002211732*T*T*R + 0.00072546*T*R*R - 0.000003582*T*T*R*R
        " | bc -l)
        (( $(echo "$HI < $T" | bc -l) )) && HI="$T"
    fi
    if (( $(echo "$T <= 10 && $W >= 5" | bc -l) )); then
        HI=$(echo "
            scale=4
            13.12 + 0.6215*$T - 11.37*($W^0.16) + 0.3965*$T*($W^0.16)
        " | bc -l)
    fi
    # Round to 2 decimals
    printf "%.2f" "$HI"
}

# ------------------------
# Enhanced Advice generator with intensity levels
# ------------------------
give_advice() {
    case "$1" in
        # Temperature alerts
        "heat_extreme") echo "🔥 Extreme heat! Stay indoors with AC, hydrate constantly" ;;
        "heat_high") echo "🥵 High heat! Avoid sun, drink plenty of water" ;;
        "heat_mild") echo "☀️ Warm weather - stay hydrated" ;;
        "cold_extreme") echo "🥶 Extreme cold! Limit outdoor exposure, wear layers" ;;
        "cold_high") echo "❄️ Very cold! Dress warmly, protect exposed skin" ;;
        "cold_mild") echo "🧥 Chilly - wear a jacket" ;;

        # Humidity alerts
        "humidity_extreme") echo "💦 Extreme humidity! Avoid exertion, use AC/dehumidifier" ;;
        "humidity_high") echo "💧 High humidity! Stay cool, drink water" ;;
        "humidity_moderate") echo "💧 Humid - stay comfortable" ;;

        # Rain intensity alerts
        "rain_light") echo "🌧 Light rain - might want an umbrella" ;;
        "rain_moderate") echo "🌧️ Moderate rain - take an umbrella" ;;
        "rain_heavy") echo "🌧️ Heavy rain - stay indoors if possible" ;;
        "rain_storm") echo "⛈ Storming! Seek shelter, avoid travel" ;;

        # Wind intensity alerts
        "wind_light") echo "💨 Light breeze - pleasant conditions" ;;
        "wind_moderate") echo "🌬 Moderate wind - secure loose objects" ;;
        "wind_strong") echo "💨 Strong wind! Be cautious outdoors" ;;
        "wind_storm") echo "🌪️ Storm-force wind! Stay indoors" ;;

        # UV intensity alerts
        "uv_low") echo "☀️ Low UV - minimal protection needed" ;;
        "uv_moderate") echo "🔆 Moderate UV - sunscreen recommended" ;;
        "uv_high") echo "😎 High UV - use sunscreen, seek shade" ;;
        "uv_extreme") echo "🔥 Extreme UV! Maximum protection required" ;;

        # Weather phenomena
        "thunderstorm") echo "⚡ Stay indoors and unplug electronics" ;;
        "fog") echo "🌫 Low visibility - drive carefully" ;;
        "snow") echo "❄️ Snow - dress warmly, drive safely" ;;
        *) echo "" ;;
    esac
}

# ------------------------
# Location detection
# ------------------------
get_location() {
    LOC=$(curl -s ipinfo.io/loc)
    LAT=$(echo "$LOC" | cut -d, -f1)
    LON=$(echo "$LOC" | cut -d, -f2)
    CITY=$(curl -s "https://nominatim.openstreetmap.org/reverse?lat=$LAT&lon=$LON&format=json" \
        | jq -r '.address.city // .address.town // .address.village // .address.hamlet // "Unknown"')
    echo "Location detected: $CITY ($LAT,$LON)"
}

# ------------------------
# Weather fetch
# ------------------------
get_weather() {
    DATA=$(curl -s "$API?latitude=$LAT&longitude=$LON&current_weather=true&hourly=temperature_2m,relative_humidity_2m,precipitation,uv_index,weathercode&forecast_days=2&timezone=auto")

    TEMP_C=$(echo "$DATA" | jq -r .current_weather.temperature)
    WIND_KPH=$(echo "$DATA" | jq -r .current_weather.windspeed)
    WEATHER_CODE=$(echo "$DATA" | jq -r .current_weather.weathercode)
    CURRENT_HOUR=$(echo "$DATA" | jq -r .current_weather.time | cut -dT -f2 | cut -d: -f1)

    HOUR_INDEX=$CURRENT_HOUR
    HUMIDITY=$(echo "$DATA" | jq -r ".hourly.relative_humidity_2m[$HOUR_INDEX]")
    PRECIP_MM=$(echo "$DATA" | jq -r ".hourly.precipitation[$HOUR_INDEX]")
    UV=$(echo "$DATA" | jq -r ".hourly.uv_index[$HOUR_INDEX]")

    FEELS_LIKE=$(calculate_feels_like "$TEMP_C" "$HUMIDITY" "$WIND_KPH")

    FORECAST_MAX_UV=$(echo "$DATA" | jq -r ".hourly.uv_index | max")
    FORECAST_MAX_TEMP=$(echo "$DATA" | jq -r ".hourly.temperature_2m | max")
    FORECAST_MIN_TEMP=$(echo "$DATA" | jq -r ".hourly.temperature_2m | min")

    # Next 3 hours forecast (wrap around to next day if needed)
    NEXT3_RAIN=()
    NEXT3_TEMP=()
    NEXT3_TIME=()
    for i in 1 2 3; do
        idx=$((HOUR_INDEX+i))
        # wrap around total hours (48 for 2-day hourly)
        idx=$(( idx % $(echo "$DATA" | jq -r '.hourly.time | length') ))
        r=$(echo "$DATA" | jq -r ".hourly.precipitation[$idx]")
        t=$(echo "$DATA" | jq -r ".hourly.time[$idx]" | cut -dT -f2 | cut -d: -f1)
        temp=$(echo "$DATA" | jq -r ".hourly.temperature_2m[$idx]")
        NEXT3_RAIN+=("$r")
        NEXT3_TIME+=("$t:00")
        NEXT3_TEMP+=("$temp")
    done
}

# ------------------------
# Enhanced Notifications with intensity levels
# ------------------------
send_notifications() {
    MESSAGE=""

    # Alerts (current dangerous conditions with intensity levels)
    ALERTS=()

    # Temperature alerts
    if (( $(echo "$FEELS_LIKE >= 40" | bc -l) )); then
        ALERTS+=("🔥 Extreme heat (${FEELS_LIKE}°C) → $(give_advice heat_extreme)")
    elif (( $(echo "$FEELS_LIKE >= 35" | bc -l) )); then
        ALERTS+=("🥵 High heat (${FEELS_LIKE}°C) → $(give_advice heat_high)")
    elif (( $(echo "$FEELS_LIKE >= 30" | bc -l) )); then
        ALERTS+=("☀️ Warm (${FEELS_LIKE}°C) → $(give_advice heat_mild)")
    elif (( $(echo "$FEELS_LIKE <= 0" | bc -l) )); then
        ALERTS+=("🥶 Extreme cold (${FEELS_LIKE}°C) → $(give_advice cold_extreme)")
    elif (( $(echo "$FEELS_LIKE <= 5" | bc -l) )); then
        ALERTS+=("❄️ Very cold (${FEELS_LIKE}°C) → $(give_advice cold_high)")
    elif (( $(echo "$FEELS_LIKE <= 10" | bc -l) )); then
        ALERTS+=("🧥 Chilly (${FEELS_LIKE}°C) → $(give_advice cold_mild)")
    fi

    # Humidity alerts
    if (( $(echo "$HUMIDITY >= 90" | bc -l) )); then
        ALERTS+=("💦 Extreme humidity (${HUMIDITY}%) → $(give_advice humidity_extreme)")
    elif (( $(echo "$HUMIDITY >= 80" | bc -l) )); then
        ALERTS+=("💧 High humidity (${HUMIDITY}%) → $(give_advice humidity_high)")
    elif (( $(echo "$HUMIDITY >= 70" | bc -l) )); then
        ALERTS+=("💧 Humid (${HUMIDITY}%) → $(give_advice humidity_moderate)")
    fi

    # Rain alerts
    if (( $(echo "$PRECIP_MM > 0" | bc -l) )); then
        if (( $(echo "$PRECIP_MM >= 7.6" | bc -l) )); then
            ALERTS+=("🌧️ Heavy rain (${PRECIP_MM} mm/h) → $(give_advice rain_heavy)")
        elif (( $(echo "$PRECIP_MM >= 2.6" | bc -l) )); then
            ALERTS+=("🌧️ Moderate rain (${PRECIP_MM} mm/h) → $(give_advice rain_moderate)")
        else
            ALERTS+=("🌧 Light rain (${PRECIP_MM} mm/h) → $(give_advice rain_light)")
        fi
    fi

    # Wind alerts
    if (( $(echo "$WIND_KPH >= 62" | bc -l) )); then
        ALERTS+=("🌪️ Storm wind (${WIND_KPH} km/h) → $(give_advice wind_storm)")
    elif (( $(echo "$WIND_KPH >= 39" | bc -l) )); then
        ALERTS+=("💨 Strong wind (${WIND_KPH} km/h) → $(give_advice wind_strong)")
    elif (( $(echo "$WIND_KPH >= 20" | bc -l) )); then
        ALERTS+=("🌬 Moderate wind (${WIND_KPH} km/h) → $(give_advice wind_moderate)")
    elif (( $(echo "$WIND_KPH >= 6" | bc -l) )); then
        ALERTS+=("💨 Light breeze (${WIND_KPH} km/h) → $(give_advice wind_light)")
    fi

    # UV alerts
    if (( $(echo "$UV >= 11" | bc -l) )); then
        ALERTS+=("🔥 Extreme UV (${UV}) → $(give_advice uv_extreme)")
    elif (( $(echo "$UV >= 8" | bc -l) )); then
        ALERTS+=("😎 High UV (${UV}) → $(give_advice uv_high)")
    elif (( $(echo "$UV >= 6" | bc -l) )); then
        ALERTS+=("🔆 Moderate UV (${UV}) → $(give_advice uv_moderate)")
    elif (( $(echo "$UV >= 3" | bc -l) )); then
        ALERTS+=("☀️ Low UV (${UV}) → $(give_advice uv_low)")
    fi

    # Weather code-based alerts
    case "$WEATHER_CODE" in
        95|96|99) ALERTS+=("⛈ Thunderstorm → $(give_advice thunderstorm)") ;;
        45|48) ALERTS+=("🌫 Fog → $(give_advice fog)") ;;
        71|73|75|77|85|86) ALERTS+=("❄️ Snow → $(give_advice snow)") ;;
    esac

    # ------------------------
    # Build message
    # ------------------------
    if (( ${#ALERTS[@]} > 0 )); then
        MESSAGE+="🚨 Alerts:\n"
        for a in "${ALERTS[@]}"; do
            MESSAGE+="• $a\n"
        done
        MESSAGE+="\n"
    fi

    # Current conditions (exclude duplicated alerts)
    MESSAGE+="📊 Current:\n"

    # Temperature
    temp_alert_exists=0
    for alert in "${ALERTS[@]}"; do
        if [[ "$alert" == *"heat"* || "$alert" == *"cold"* || "$alert" == *"Warm"* || "$alert" == *"Chilly"* ]]; then
            temp_alert_exists=1
            break
        fi
    done
    [[ $temp_alert_exists -eq 0 ]] && MESSAGE+="• Temp: ${TEMP_C}°C (Feels like ${FEELS_LIKE}°C 🌡)\n"

    # Humidity
    humidity_alert_exists=0
    for alert in "${ALERTS[@]}"; do
        if [[ "$alert" == *"humidity"* || "$alert" == *"Humid"* ]]; then
            humidity_alert_exists=1
            break
        fi
    done
    [[ $humidity_alert_exists -eq 0 ]] && MESSAGE+="• Humidity: ${HUMIDITY}%\n"

    MESSAGE+="• Wind: ${WIND_KPH} km/h\n"

    # Rain
    rain_alert_exists=0
    for alert in "${ALERTS[@]}"; do
        if [[ "$alert" == *"rain"* || "$alert" == *"Rain"* ]]; then
            rain_alert_exists=1
            break
        fi
    done
    [[ $rain_alert_exists -eq 0 ]] && MESSAGE+="• Rain: ${PRECIP_MM} mm\n"

    # UV
    uv_alert_exists=0
    for alert in "${ALERTS[@]}"; do
        if [[ "$alert" == *"UV"* ]]; then
            uv_alert_exists=1
            break
        fi
    done
    [[ $uv_alert_exists -eq 0 ]] && MESSAGE+="• UV Index: $UV\n"

    MESSAGE+="\n"

    # ------------------------
    # Forecast: next 3h + daily high/low + peak UV
    # ------------------------
    MESSAGE+="📅 Forecast:\n"
    for i in "${!NEXT3_RAIN[@]}"; do
        rain="${NEXT3_RAIN[$i]}"
        time="${NEXT3_TIME[$i]}"

        if (( $(echo "$rain > 0" | bc -l) )); then
            if (( $(echo "$rain >= 7.6" | bc -l) )); then
                key="rain_heavy"
            elif (( $(echo "$rain >= 2.6" | bc -l) )); then
                key="rain_moderate"
            else
                key="rain_light"
            fi
            MESSAGE+="• $time → $rain mm ☔ ($(give_advice $key))\n"
        else
            MESSAGE+="• $time → $rain mm ✅ No rain\n"
        fi
    done

    # Today's High/Low temperature advice
    if (( $(echo "$FORECAST_MAX_TEMP >= 30" | bc -l) )); then
        high_advice=$(give_advice heat_mild)
    elif (( $(echo "$FORECAST_MAX_TEMP >= 35" | bc -l) )); then
        high_advice=$(give_advice heat_high)
    else
        high_advice=$(give_advice heat_mild)
    fi

    if (( $(echo "$FORECAST_MIN_TEMP <= 0" | bc -l) )); then
        low_advice=$(give_advice cold_extreme)
    elif (( $(echo "$FORECAST_MIN_TEMP <= 10" | bc -l) )); then
        low_advice=$(give_advice cold_mild)
    else
        low_advice=$(give_advice cold_mild)
    fi

    MESSAGE+="• Today's High: ${FORECAST_MAX_TEMP}°C 🌡 ($high_advice)\n"
    MESSAGE+="• Today's Low: ${FORECAST_MIN_TEMP}°C 🧥 ($low_advice)\n"

    # Peak UV advice
    if (( $(echo "$FORECAST_MAX_UV >= 11" | bc -l) )); then
        uv_advice=$(give_advice uv_extreme)
    elif (( $(echo "$FORECAST_MAX_UV >= 8" | bc -l) )); then
        uv_advice=$(give_advice uv_high)
    elif (( $(echo "$FORECAST_MAX_UV >= 6" | bc -l) )); then
        uv_advice=$(give_advice uv_moderate)
    else
        uv_advice=$(give_advice uv_low)
    fi

    MESSAGE+="• Peak UV Today: ${FORECAST_MAX_UV} 🔆 ($uv_advice)\n"

    TITLE="⛅ Weather $CITY"
    notify-send -u critical "$TITLE" "$MESSAGE"
}

# ------------------------
# Main loop
# ------------------------
check_dependencies() {
    for dep in curl jq bc notify-send; do
        command -v "$dep" >/dev/null || { echo "Missing $dep"; exit 1; }
    done
}

main() {
    check_dependencies
    get_location
    while true; do
        get_weather
        send_notifications
        sleep "$INTERVAL"
    done
}

main
