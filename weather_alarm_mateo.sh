#!/usr/bin/env bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"

# Weather Alarm Script (Open-Meteo)

# - Alerts (current dangerous conditions only, with advice)

# - Current (safe values only, no duplication from alerts)

# - Forecast (hourly breakdown for next 3h + today's min/max + peak UV, with advice)

# - Added: Wind direction + Pollution index (PM2.5/AQI) with ranges and alerts


API="https://api.open-meteo.com/v1/forecast"
AIR_API="https://air-quality-api.open-meteo.com/v1/air-quality"
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
# Wind direction conversion
# ------------------------
wind_degree_to_direction() {
    local degrees="$1"

    if (( $(echo "$degrees >= 337.5 || $degrees < 22.5" | bc -l) )); then
        echo "N"
    elif (( $(echo "$degrees >= 22.5 && $degrees < 67.5" | bc -l) )); then
        echo "NE"
    elif (( $(echo "$degrees >= 67.5 && $degrees < 112.5" | bc -l) )); then
        echo "E"
    elif (( $(echo "$degrees >= 112.5 && $degrees < 157.5" | bc -l) )); then
        echo "SE"
    elif (( $(echo "$degrees >= 157.5 && $degrees < 202.5" | bc -l) )); then
        echo "S"
    elif (( $(echo "$degrees >= 202.5 && $degrees < 247.5" | bc -l) )); then
        echo "SW"
    elif (( $(echo "$degrees >= 247.5 && $degrees < 292.5" | bc -l) )); then
        echo "W"
    elif (( $(echo "$degrees >= 292.5 && $degrees < 337.5" | bc -l) )); then
        echo "NW"
    else
        echo "Unknown"
    fi
}


# ------------------------
# Pollution level classification
# ------------------------
get_pollution_level() {
    local aqi="$1"
    local pm25="$2"

    if (( $(echo "$aqi >= 301" | bc -l) )); then
        echo "extreme"
    elif (( $(echo "$aqi >= 201" | bc -l) )); then
        echo "very_unhealthy"
    elif (( $(echo "$aqi >= 101" | bc -l) )); then
        echo "high"
    elif (( $(echo "$aqi >= 51" | bc -l) )); then
        echo "moderate"
    else
        echo "light"
    fi
}


# ------------------------
# Pollution level emoji + text
# ------------------------
pollution_level_to_text() {
    case "$1" in
        "extreme") echo "☠️ Extreme" ;;
        "very_unhealthy") echo "⚠️ Very Unhealthy" ;;
        "high") echo "🌫️ High" ;;
        "moderate") echo "💨 Moderate" ;;
        "light") echo "✅ Light" ;;
        *) echo "❓ Unknown" ;;
    esac
}


# ------------------------
# Feels-like calculation
# ------------------------
calculate_feels_like() {
    local T="$1" H="$2" W="$3"
    local HI="$T"

    # Heat Index (>=27°C, >40% humidity)
    if (( $(echo "$T >= 27 && $H > 40" | bc -l) )); then
        HI=$(echo "scale=4; -8.784695 + 1.61139411*$T + 2.338549*$H - 0.14611605*$T*$H - 0.012308094*$T*$T - 0.016424828*$H*$H + 0.002211732*$T*$T*$H + 0.00072546*$T*$H*$H - 0.000003582*$T*$T*$H*$H" | bc -l)
        if (( $(echo "$HI < $T" | bc -l) )); then
            HI="$T"
        fi
    fi

    # Wind Chill (<=10°C, wind >=5 km/h)
    if (( $(echo "$T <= 10 && $W >= 5" | bc -l) )); then
        HI=$(echo "scale=4; 13.12 + 0.6215*$T - 11.37*($W^0.16) + 0.3965*$T*($W^0.16)" | bc -l)
    fi

    printf "%.2f" "$HI"
}


# ------------------------
# Advice generator
# ------------------------
give_advice() {
    case "$1" in
        "heat_extreme") echo "🔥 Extreme heat! Stay indoors with AC, hydrate constantly" ;;
        "heat_high") echo "🥵 High heat! Avoid sun, drink plenty of water" ;;
        "heat_mild") echo "☀️ Warm weather - stay hydrated" ;;
        "cold_extreme") echo "🥶 Extreme cold! Limit outdoor exposure, wear layers" ;;
        "cold_high") echo "❄️ Very cold! Dress warmly, protect exposed skin" ;;
        "cold_mild") echo "🧥 Chilly - wear a jacket" ;;
        "humidity_extreme") echo "💦 Extreme humidity! Avoid exertion, use AC/dehumidifier" ;;
        "humidity_high") echo "💧 High humidity! Stay cool, drink water" ;;
        "humidity_moderate") echo "💧 Humid - stay comfortable" ;;
        "rain_light") echo "🌧 Light rain - might want an umbrella" ;;
        "rain_moderate") echo "🌧️ Moderate rain - take an umbrella" ;;
        "rain_heavy") echo "🌧️ Heavy rain - stay indoors if possible" ;;
        "rain_storm") echo "⛈ Storming! Seek shelter, avoid travel" ;;
        "wind_light") echo "💨 Light breeze - pleasant conditions" ;;
        "wind_moderate") echo "🌬 Moderate wind - secure loose objects" ;;
        "wind_strong") echo "💨 Strong wind! Be cautious outdoors" ;;
        "wind_storm") echo "🌪️ Storm-force wind! Stay indoors" ;;
        "uv_low") echo "☀️ Low UV - minimal protection needed" ;;
        "uv_moderate") echo "🔆 Moderate UV - sunscreen recommended" ;;
        "uv_high") echo "😎 High UV - use sunscreen, seek shade" ;;
        "uv_extreme") echo "🔥 Extreme UV! Maximum protection required" ;;
        "thunderstorm") echo "⚡ Stay indoors and unplug electronics" ;;
        "fog") echo "🌫 Low visibility - drive carefully" ;;
        "snow") echo "❄️ Snow - dress warmly, drive safely" ;;
        "pollution_light") echo "✅ Good air quality - enjoy outdoor activities" ;;
        "pollution_moderate") echo "💨 Moderate air quality - sensitive individuals should reduce outdoor exertion" ;;
        "pollution_high") echo "🌫️ Poor air quality! Wear a mask, avoid outdoor activity" ;;
        "pollution_very_unhealthy") echo "⚠️ Very unhealthy air! Everyone should avoid outdoor activities" ;;
        "pollution_extreme") echo "☠️ Hazardous air quality! Stay indoors, use purifier if possible" ;;
        *) echo "" ;;
    esac
}


# ------------------------
# Location detection (your original with fallbacks)
# ------------------------
get_location() {
    LOC=$(curl -s ipinfo.io/loc)
    LAT=$(echo "$LOC" | cut -d, -f1)
    LON=$(echo "$LOC" | cut -d, -f2)

    if [[ -z "$LAT" || -z "$LON" ]]; then
        LOC=$(curl -s ipapi.co/latlong)
        LAT=$(echo "$LOC" | cut -d, -f1)
        LON=$(echo "$LOC" | cut -d, -f2)
    fi

    if [[ -z "$LAT" || -z "$LON" ]]; then
        LAT=$(curl -s freegeoip.app/json/ | jq -r '.latitude')
        LON=$(curl -s freegeoip.app/json/ | jq -r '.longitude')
    fi

    if [[ -z "$LAT" || -z "$LON" ]]; then
        echo "❌ Could not determine location" >&2
        exit 1
    fi

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
    WIND_DEG=$(echo "$DATA" | jq -r .current_weather.winddirection)
    WIND_DIR=$(wind_degree_to_direction "$WIND_DEG")
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

    # Next 3 hours forecast
    NEXT3_RAIN=()
    NEXT3_TEMP=()
    NEXT3_TIME=()
    for i in 1 2 3; do
        idx=$((10#$HOUR_INDEX+i))
        idx=$(( idx % $(echo "$DATA" | jq -r '.hourly.time | length') ))
        r=$(echo "$DATA" | jq -r ".hourly.precipitation[$idx]")
        t=$(echo "$DATA" | jq -r ".hourly.time[$idx]" | cut -dT -f2 | cut -d: -f1)
        temp=$(echo "$DATA" | jq -r ".hourly.temperature_2m[$idx]")
        NEXT3_RAIN+=("$r")
        NEXT3_TIME+=("$t:00")
        NEXT3_TEMP+=("$temp")
    done

    # --- Pollution data (PM2.5 & AQI) ---
    AIR=$(curl -s "$AIR_API?latitude=$LAT&longitude=$LON&current=pm2_5,european_aqi")
    PM25=$(echo "$AIR" | jq -r .current.pm2_5)
    AQI=$(echo "$AIR" | jq -r .current.european_aqi)
    POLLUTION_LEVEL=$(get_pollution_level "$AQI" "$PM25")
    POLLUTION_TEXT=$(pollution_level_to_text "$POLLUTION_LEVEL")
}


# ------------------------
# Notifications
# ------------------------
send_notifications() {
    MESSAGE=""
    ALERTS=()

    # --- Temperature alerts ---
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

    # --- Humidity alerts ---
    if (( $(echo "$HUMIDITY >= 90" | bc -l) )); then
        ALERTS+=("💦 Extreme humidity (${HUMIDITY}%) → $(give_advice humidity_extreme)")
    elif (( $(echo "$HUMIDITY >= 80" | bc -l) )); then
        ALERTS+=("💧 High humidity (${HUMIDITY}%) → $(give_advice humidity_high)")
    elif (( $(echo "$HUMIDITY >= 70" | bc -l) )); then
        ALERTS+=("💧 Humid (${HUMIDITY}%) → $(give_advice humidity_moderate)")
    fi

    # --- Rain alerts ---
    if (( $(echo "$PRECIP_MM > 0" | bc -l) )); then
        if (( $(echo "$PRECIP_MM >= 7.6" | bc -l) )); then
            ALERTS+=("🌧️ Heavy rain (${PRECIP_MM} mm/h) → $(give_advice rain_heavy)")
        elif (( $(echo "$PRECIP_MM >= 2.6" | bc -l) )); then
            ALERTS+=("🌧️ Moderate rain (${PRECIP_MM} mm/h) → $(give_advice rain_moderate)")
        else
            ALERTS+=("🌧 Light rain (${PRECIP_MM} mm/h) → $(give_advice rain_light)")
        fi
    fi

    # --- Wind alerts ---
    if (( $(echo "$WIND_KPH >= 62" | bc -l) )); then
        ALERTS+=("🌪️ Storm wind (${WIND_KPH} km/h) → $(give_advice wind_storm)")
    elif (( $(echo "$WIND_KPH >= 39" | bc -l) )); then
        ALERTS+=("💨 Strong wind (${WIND_KPH} km/h) → $(give_advice wind_strong)")
    elif (( $(echo "$WIND_KPH >= 20" | bc -l) )); then
        ALERTS+=("🌬 Moderate wind (${WIND_KPH} km/h) → $(give_advice wind_moderate)")
    elif (( $(echo "$WIND_KPH >= 6" | bc -l) )); then
        ALERTS+=("💨 Light breeze (${WIND_KPH} km/h) → $(give_advice wind_light)")
    fi

    # --- UV alerts ---
    if (( $(echo "$UV >= 11" | bc -l) )); then
        ALERTS+=("🔥 Extreme UV (${UV}) → $(give_advice uv_extreme)")
    elif (( $(echo "$UV >= 8" | bc -l) )); then
        ALERTS+=("😎 High UV (${UV}) → $(give_advice uv_high)")
    elif (( $(echo "$UV >= 6" | bc -l) )); then
        ALERTS+=("🔆 Moderate UV (${UV}) → $(give_advice uv_moderate)")
    elif (( $(echo "$UV >= 3" | bc -l) )); then
        ALERTS+=("☀️ Low UV (${UV}) → $(give_advice uv_low)")
    fi

    # --- Pollution alerts ---
    if [[ "$POLLUTION_LEVEL" == "extreme" ]]; then
        ALERTS+=("☠️ Extreme pollution (AQI $AQI, PM2.5 $PM25 µg/m³) → $(give_advice pollution_extreme)")
    elif [[ "$POLLUTION_LEVEL" == "very_unhealthy" ]]; then
        ALERTS+=("⚠️ Very unhealthy pollution (AQI $AQI, PM2.5 $PM25 µg/m³) → $(give_advice pollution_very_unhealthy)")
    elif [[ "$POLLUTION_LEVEL" == "high" ]]; then
        ALERTS+=("🌫️ High pollution (AQI $AQI, PM2.5 $PM25 µg/m³) → $(give_advice pollution_high)")
    elif [[ "$POLLUTION_LEVEL" == "moderate" ]]; then
        ALERTS+=("💨 Moderate pollution (AQI $AQI, PM2.5 $PM25 µg/m³) → $(give_advice pollution_moderate)")
    fi

    # --- Weather code-based alerts ---
    case "$WEATHER_CODE" in
        95|96|99) ALERTS+=("⛈ Thunderstorm → $(give_advice thunderstorm)") ;;
        45|48) ALERTS+=("🌫 Fog → $(give_advice fog)") ;;
        71|73|75|77|85|86) ALERTS+=("❄️ Snow → $(give_advice snow)") ;;
    esac

    # ------------------------
    # Build alert message
    # ------------------------
    if (( ${#ALERTS[@]} > 0 )); then
        MESSAGE+="🚨 Alerts:\n"
        for a in "${ALERTS[@]}"; do
            MESSAGE+="• $a\n"
        done
        MESSAGE+="\n"
    fi

    # ------------------------
    # Current conditions
    # ------------------------
    MESSAGE+="📊 Current:\n"
    [[ ! ${ALERTS[*]} =~ "heat" && ! ${ALERTS[*]} =~ "cold" ]] && \
        MESSAGE+="• Temp: ${TEMP_C}°C (Feels like ${FEELS_LIKE}°C 🌡)\n"
    [[ ! ${ALERTS[*]} =~ "humidity" ]] && \
        MESSAGE+="• Humidity: ${HUMIDITY}%\n"
    MESSAGE+="• Wind: ${WIND_KPH} km/h ${WIND_DIR} ${WIND_DEG}°\n"
    [[ ! ${ALERTS[*]} =~ "rain" ]] && \
        MESSAGE+="• Rain: ${PRECIP_MM} mm\n"
    [[ ! ${ALERTS[*]} =~ "UV" ]] && \
        MESSAGE+="• UV Index: $UV\n"
    MESSAGE+="• Air Quality: AQI ${AQI}, PM2.5 ${PM25} µg/m³ (${POLLUTION_TEXT})\n\n"

    # ------------------------
    # Forecast (next 3h + daily)
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

    # Daily highs/lows
    high_advice=$( (( $(echo "$FORECAST_MAX_TEMP >= 35" | bc -l) )) && echo "$(give_advice heat_high)" || echo "$(give_advice heat_mild)" )
    low_advice=$( (( $(echo "$FORECAST_MIN_TEMP <= 0" | bc -l) )) && echo "$(give_advice cold_extreme)" || echo "$(give_advice cold_mild)" )

    MESSAGE+="• Today's High: ${FORECAST_MAX_TEMP}°C 🌡 ($high_advice)\n"
    MESSAGE+="• Today's Low: ${FORECAST_MIN_TEMP}°C ❄️ ($low_advice)\n"

    if (( $(echo "$FORECAST_MAX_UV >= 8" | bc -l) )); then
        uv_key="uv_high"
    elif (( $(echo "$FORECAST_MAX_UV >= 6" | bc -l) )); then
        uv_key="uv_moderate"
    elif (( $(echo "$FORECAST_MAX_UV >= 3" | bc -l) )); then
        uv_key="uv_low"
    else
        uv_key=""
    fi
    [[ -n $uv_key ]] && MESSAGE+="• Peak UV: ${FORECAST_MAX_UV} 🌞 ($(give_advice $uv_key))\n"

    # ------------------------
    # Send notification
    # ------------------------
    notify-send "Weather Update - $CITY" "$MESSAGE"
#     kdialog --title "Weather Update - $CITY" --msgbox "$MESSAGE"
    echo -e "$MESSAGE"
}


# ------------------------
# Main loop
# ------------------------
main() {
    get_location
    get_weather
    send_notifications
}

while true; do
    main
    sleep $INTERVAL
done
