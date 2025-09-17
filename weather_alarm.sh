#!/usr/bin/env bash
# Weather Alarm Script - Human-Advice Version
# Dependencies: curl, jq, bc, notify-send

API_KEY="98ddb8a158f24a1596882148251309"
BASE_URL="http://api.weatherapi.com/v1"
INTERVAL=900       # 15 minutes
ALERT_WINDOW=30    # Minutes before astronomical events

# ------------------------
# Utilities
# ------------------------
deg_to_dir() {
    local deg="$1"
    # Validate input
    if ! [[ "$deg" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        echo "Unknown"
        return 1
    fi

    # Normalize to 0-360
    deg=$(echo "scale=0; ($deg + 360) % 360" | bc -l)

    local directions=("N" "NE" "E" "SE" "S" "SW" "W" "NW")
    local idx=$(( (deg + 22) / 45 % 8 ))

    echo "${directions[$idx]}"
}

calculate_feels_like() {
    local T="$1" H="$2" W="$3"
    local HI="$T"
    if (( $(echo "$T >= 27 && $H > 40" | bc -l) )); then
        HI=$(echo "scale=2; -8.784695 + 1.61139411*$T + 2.338549*$H - 0.14611605*$T*$H - 0.012308094*$T*$T - 0.016424828*$H*$H + 0.002211732*$T*$T*$H + 0.00072546*$T*$H*$H - 0.000003582*$T*$T*$H*$H" | bc -l)
        (( $(echo "$HI < $T" | bc -l) )) && HI="$T"
    fi
    if (( $(echo "$T <= 10 && $W >= 5" | bc -l) )); then
        HI=$(echo "scale=2; 13.12 + 0.6215*$T - 11.37*($W^0.16) + 0.3965*$T*($W^0.16)" | bc -l)
    fi
    printf "%.1f" "$HI"
}

give_advice() {
    case "$1" in
        # Temperature
        "heat_extreme") echo "Stay indoors; use AC, hydrate constantly" ;;
        "heat_high") echo "Avoid direct sun; drink plenty of water" ;;
        "heat_mild") echo "Hydrate to stay comfortable" ;;
        "heat_low") echo "Enjoy the pleasant weather" ;;
        "cold_extreme") echo "Limit outdoor time; wear multiple layers" ;;
        "cold_high") echo "Dress warmly with a heavy coat" ;;
        "cold_mild") echo "A light jacket is recommended" ;;
        "cold_low") echo "Dress comfortably for a mild day" ;;
        # Humidity
        "humidity_extreme") echo "Use AC or dehumidifier indoors" ;;
        "humidity_high") echo "Stay cool; avoid strenuous activity" ;;
        "humidity_moderate") echo "The air feels a bit heavy" ;;
        "humidity_low") echo "Stay hydrated; air may be dry" ;;
        # Rain
        "rain_storm") echo "Seek shelter; avoid travel" ;;
        "rain_heavy") echo "Stay indoors; flash flood risk" ;;
        "rain_moderate") echo "Use an umbrella for moderate rain" ;;
        "rain_light") echo "Light rain, an umbrella should suffice" ;;
        "rain_none") echo "No rain expected" ;;
        # Wind
        "wind_storm") echo "Stay indoors; risk of damage" ;;
        "wind_strong") echo "Be cautious; secure outdoor items" ;;
        "wind_moderate") echo "A steady, noticeable breeze" ;;
        "wind_light") echo "Gentle breeze, pleasant conditions" ;;
        "wind_none") echo "Calm winds" ;;
        # UV
        "uv_extreme") echo "Maximum protection; stay in the shade" ;;
        "uv_high") echo "Apply sunscreen; wear hat and sunglasses" ;;
        "uv_moderate") echo "Take precautions; wear sunscreen" ;;
        "uv_low") echo "Low risk; enjoy the sun" ;;
        # Pollution
        "pollution_extreme") echo "Hazardous air quality, stay indoors" ;;
        "pollution_very_unhealthy") echo "Very unhealthy, avoid outdoor activities" ;;
        "pollution_high") echo "Poor air quality, limit outdoor exposure" ;;
        "pollution_moderate") echo "Moderate pollution, stay cautious" ;;
        "pollution_light") echo "" ;;
        # Weather phenomena
        "thunderstorm") echo "Thunderstorm, stay indoors" ;;
        "fog") echo "Low visibility, drive carefully" ;;
        "snow") echo "Snowy conditions, dress warmly and drive safely" ;;
        # Astronomy
        "sunrise") echo "Sunrise soon" ;;
        "sunset") echo "Sunset soon" ;;
        "moonrise") echo "Moonrise soon" ;;
        "moonset") echo "Moonset soon" ;;
        "full_moon") echo "Full Moon" ;;
        "new_moon") echo "New Moon" ;;
        "first_quarter") echo "First Quarter Moon" ;;
        "last_quarter") echo "Last Quarter Moon" ;;
        "eclipse") echo "Eclipse today" ;;
        *) echo "" ;;
    esac
}

# ------------------------
# Location detection with fallbacks
# ------------------------
get_location() {
    LOC=$(curl -s ipinfo.io/loc 2>/dev/null)
    [[ -z "$LOC" ]] && LOC=$(curl -s ipapi.co/latlong 2>/dev/null)
    [[ -z "$LOC" ]] && LOC=$(curl -s ifconfig.me 2>/dev/null)
    LAT=$(echo "$LOC" | cut -d, -f1)
    LON=$(echo "$LOC" | cut -d, -f2)
    CITY=$(curl -s "https://nominatim.openstreetmap.org/reverse?lat=$LAT&lon=$LON&format=json" \
        | jq -r '.address.city // .address.town // .address.village // .address.hamlet // "Unknown"')
    echo "Location detected: $CITY ($LAT,$LON)"
}

# ------------------------
# Fetch weather & astronomy
# ------------------------
get_weather() {
    FORECAST=$(curl -s "$BASE_URL/forecast.json?key=$API_KEY&q=$LAT,$LON&days=2&aqi=yes&alerts=yes")
    ASTRONOMY=$(curl -s "$BASE_URL/astronomy.json?key=$API_KEY&q=$LAT,$LON")

    TEMP_C=$(echo "$FORECAST" | jq -r '.current.temp_c // 0')
    FEELS=$(echo "$FORECAST" | jq -r '.current.feelslike_c // 0')
    HUMIDITY=$(echo "$FORECAST" | jq -r '.current.humidity // 0')
    WIND_KPH=$(echo "$FORECAST" | jq -r '.current.wind_kph // 0')
    WIND_DIR_DEG=$(echo "$FORECAST" | jq -r '.current.wind_degree // 0')
    WIND_DIR=$(deg_to_dir "$WIND_DIR_DEG")
    PRECIP=$(echo "$FORECAST" | jq -r '.current.precip_mm // 0')
    UV=$(echo "$FORECAST" | jq -r '.current.uv // 0')
    VIS=$(echo "$FORECAST" | jq -r '.current.vis_km // 0')
    CONDITION=$(echo "$FORECAST" | jq -r '.current.condition.text // ""')
    AQI=$(echo "$FORECAST" | jq -r '.current.air_quality["us-epa-index"] // 0')
    PM25=$(echo "$FORECAST" | jq -r '.current.air_quality.pm2_5 // 0')

    MAX_TEMP=$(echo "$FORECAST" | jq -r '.forecast.forecastday[0].day.maxtemp_c // 0')
    MIN_TEMP=$(echo "$FORECAST" | jq -r '.forecast.forecastday[0].day.mintemp_c // 0')
    PEAK_UV=$(echo "$FORECAST" | jq -r '.forecast.forecastday[0].day.uv // 0')

    SUNRISE=$(echo "$ASTRONOMY" | jq -r '.astronomy.astro.sunrise // ""')
    SUNSET=$(echo "$ASTRONOMY" | jq -r '.astronomy.astro.sunset // ""')
    MOONRISE=$(echo "$ASTRONOMY" | jq -r '.astronomy.astro.moonrise // ""')
    MOONSET=$(echo "$ASTRONOMY" | jq -r '.astronomy.astro.moonset // ""')
    MOON_PHASE=$(echo "$ASTRONOMY" | jq -r '.astronomy.astro.moon_phase // ""')
    ECLIPSE=""  # optional
}

# ------------------------
# Generate alerts
# ------------------------
generate_alerts() {
    ALERTS=()

    # Temperature
    (( $(echo "$TEMP_C >= 40" | bc -l) )) && ALERTS+=("🔥 Extreme heat ($TEMP_C°C) → $(give_advice heat_extreme)")
    (( $(echo "$TEMP_C >= 35 && $TEMP_C < 40" | bc -l) )) && ALERTS+=("🥵 High heat ($TEMP_C°C) → $(give_advice heat_high)")
    (( $(echo "$TEMP_C >= 30 && $TEMP_C < 35" | bc -l) )) && ALERTS+=("☀️ Warm ($TEMP_C°C) → $(give_advice heat_mild)")
    (( $(echo "$TEMP_C >= 0 && $TEMP_C < 30" | bc -l) )) && ALERTS+=("🌤 Mild ($TEMP_C°C) → $(give_advice heat_low)")
    (( $(echo "$TEMP_C < 0" | bc -l) )) && ALERTS+=("🥶 Extreme cold ($TEMP_C°C) → $(give_advice cold_extreme)")

    # Humidity
    (( $(echo "$HUMIDITY >= 90" | bc -l) )) && ALERTS+=("💦 Extreme humidity ($HUMIDITY%) → $(give_advice humidity_extreme)")
    (( $(echo "$HUMIDITY >= 80 && $HUMIDITY < 90" | bc -l) )) && ALERTS+=("💧 High humidity ($HUMIDITY%) → $(give_advice humidity_high)")
    (( $(echo "$HUMIDITY >= 60 && $HUMIDITY < 80" | bc -l) )) && ALERTS+=("💧 Moderate humidity ($HUMIDITY%) → $(give_advice humidity_moderate)")
    (( $(echo "$HUMIDITY < 60" | bc -l) )) && ALERTS+=("💨 Low humidity ($HUMIDITY%) → $(give_advice humidity_low)")

    # Rain
    (( $(echo "$PRECIP >= 50" | bc -l) )) && ALERTS+=("⛈ Storming ($PRECIP mm) → $(give_advice rain_storm)")
    (( $(echo "$PRECIP >= 20 && $PRECIP < 50" | bc -l) )) && ALERTS+=("🌧 Heavy rain ($PRECIP mm) → $(give_advice rain_heavy)")
    (( $(echo "$PRECIP >= 5 && $PRECIP < 20" | bc -l) )) && ALERTS+=("🌧 Moderate rain ($PRECIP mm) → $(give_advice rain_moderate)")
    (( $(echo "$PRECIP > 0 && $PRECIP < 5" | bc -l) )) && ALERTS+=("🌦 Light rain ($PRECIP mm) → $(give_advice rain_light)")

    # Wind
    (( $(echo "$WIND_KPH >= 80" | bc -l) )) && ALERTS+=("🌪 Storm-force wind ($WIND_KPH km/h) → $(give_advice wind_storm)")
    (( $(echo "$WIND_KPH >= 40 && $WIND_KPH < 80" | bc -l) )) && ALERTS+=("💨 Strong wind ($WIND_KPH km/h) → $(give_advice wind_strong)")
    (( $(echo "$WIND_KPH >= 20 && $WIND_KPH < 40" | bc -l) )) && ALERTS+=("🌬 Moderate wind ($WIND_KPH km/h) → $(give_advice wind_moderate)")
    (( $(echo "$WIND_KPH < 20" | bc -l) )) && ALERTS+=("💨 Light breeze ($WIND_KPH km/h) → $(give_advice wind_light)")

    # UV
    (( $(echo "$UV >= 8" | bc -l) )) && ALERTS+=("🔥 Extreme UV ($UV) → $(give_advice uv_extreme)")
    (( $(echo "$UV >= 6 && $UV < 8" | bc -l) )) && ALERTS+=("😎 High UV ($UV) → $(give_advice uv_high)")
    (( $(echo "$UV >= 3 && $UV < 6" | bc -l) )) && ALERTS+=("🔆 Moderate UV ($UV) → $(give_advice uv_moderate)")

    # Pollution
    # Pollution
    case "$AQI" in
        0)
            # No alert, show in Current section later
            ;;
        1)
            ALERTS+=("🌫 Moderate pollution (AQI $AQI, PM2.5: $PM25 µg/m³) → $(give_advice pollution_moderate)")
            ;;
        2)
            ALERTS+=("☠️ Poor air quality (AQI $AQI, PM2.5: $PM25 µg/m³) → $(give_advice pollution_high)")
            ;;
        3)
            ALERTS+=("☠️ Very Unhealthy (AQI $AQI, PM2.5: $PM25 µg/m³) → $(give_advice pollution_very_unhealthy)")
            ;;
        4)
            ALERTS+=("☠️☠️ Hazardous (AQI $AQI, PM2.5: $PM25 µg/m³) → $(give_advice pollution_extreme)")
            ;;
    esac

    # Weather phenomena
    [[ "$CONDITION" =~ [Tt]hunder|[Ll]ightning|[Ss]torm ]] && ALERTS+=("⚡ Thunderstorm detected → $(give_advice thunderstorm)")
    [[ "$CONDITION" =~ [Ff]og ]] && ALERTS+=("🌫 Fog detected → $(give_advice fog)")
    [[ "$CONDITION" =~ [Ss]now ]] && ALERTS+=("❄️ Snow detected → $(give_advice snow)")
}

# ------------------------
# Astronomy alerts (localtime aware)
# ------------------------
generate_astronomy_alerts() {
    local localtime=$(echo "$FORECAST" | jq -r '.location.localtime' | cut -d' ' -f2)
    local hour=${localtime%:*}
    local minute=${localtime#*:}
    local now=$((10#$hour * 60 + 10#$minute))

    local sunrise_minutes=$(date -d "$SUNRISE" +%H:%M | awk -F: '{print ($1 * 60) + $2}')
    local sunset_minutes=$(date -d "$SUNSET" +%H:%M | awk -F: '{print ($1 * 60) + $2}')

    if (( now >= sunrise_minutes - 30 && now <= sunrise_minutes )); then
        ALERTS+=("🌅 Sunrise soon → $(give_advice sunrise)")
    elif (( now >= sunset_minutes - 30 && now <= sunset_minutes )); then
        ALERTS+=("🌇 Sunset soon → $(give_advice sunset)")
    fi

    case "$MOON_PHASE" in
        "Full Moon") ALERTS+=("🌕 Full Moon → $(give_advice fullmoon)") ;;
        "New Moon") ALERTS+=("🌑 New Moon → $(give_advice newmoon)") ;;
    esac
}


# ------------------------
# Notifications
# ------------------------
send_notifications() {
    generate_alerts
    generate_astronomy_alerts

    MESSAGE=""
    if [[ ${#ALERTS[@]} -gt 0 ]]; then
        MESSAGE+="🚨 Alerts:\n"
        for a in "${ALERTS[@]}"; do
            MESSAGE+="• $a\n"
        done
        MESSAGE+="\n"
    fi

    MESSAGE+="📊 Current ($CITY):\n"

    # Check if a temperature-related alert exists before showing current temp
    if ! grep -q -E "heat|cold" <<< "${ALERTS[@]}"; then
        MESSAGE+="• Temp: $TEMP_C°C (Feels: $FEELS°C)\n"
    fi

    # Check if a humidity alert exists
    if ! grep -q "humidity" <<< "${ALERTS[@]}"; then
        MESSAGE+="• Humidity: $HUMIDITY%\n"
    fi

    # Check if a wind alert exists
    if ! grep -q "wind" <<< "${ALERTS[@]}"; then
        MESSAGE+="• Wind: $WIND_KPH km/h ($WIND_DIR)\n"
    fi

    # Check if a rain alert exists
    if ! grep -q "rain" <<< "${ALERTS[@]}"; then
        MESSAGE+="• Rain: $PRECIP mm\n"
    fi

    # Check if a UV alert exists
    if ! grep -q "UV" <<< "${ALERTS[@]}"; then
        MESSAGE+="• UV: $UV\n"
    fi

    # Check if a pollution alert exists
    if ! grep -q -E "pollution|AQI" <<< "${ALERTS[@]}"; then
        MESSAGE+="• Air Quality: AQI $AQI (PM2.5: $PM25 µg/m³)\n"
    fi

    # Visibility is always shown as there are no alerts for it
    MESSAGE+="• Visibility: $VIS km\n\n"

    MESSAGE+="📅 Forecast:\n"
    # Get current local hour at location
    LOCAL_HOUR=$(echo "$FORECAST" | jq -r '.location.localtime' | cut -d' ' -f2 | cut -d: -f1)
    # Loop through next 6 hours, skip the current hour
    for i in {1..3}; do
        hr_time=$(echo "$FORECAST" | jq -r ".forecast.forecastday[0].hour[$((10#$LOCAL_HOUR + i))].time" | cut -d' ' -f2)
        hr_temp=$(echo "$FORECAST" | jq -r ".forecast.forecastday[0].hour[$((10#$LOCAL_HOUR + i))].temp_c")
        hr_rain=$(echo "$FORECAST" | jq -r ".forecast.forecastday[0].hour[$((10#$LOCAL_HOUR + i))].precip_mm")
        hr_advice=""
        if (( $(echo "$hr_rain >= 20" | bc -l) )); then
            hr_advice=$(give_advice rain_heavy)
        elif (( $(echo "$hr_rain >= 5 && $hr_rain < 20" | bc -l) )); then
            hr_advice=$(give_advice rain_moderate)
        elif (( $(echo "$hr_rain > 0 && $hr_rain < 5" | bc -l) )); then
            hr_advice=$(give_advice rain_light)
        fi
        MESSAGE+="• $hr_time → $hr_temp°C, $hr_rain mm"
        [[ -n "$hr_advice" ]] && MESSAGE+=" → $hr_advice"
        MESSAGE+="\n"
    done
    MESSAGE+="• High: $MAX_TEMP°C, Low: $MIN_TEMP°C\n"
    MESSAGE+="• Peak UV: $PEAK_UV$( [[ $(echo "$PEAK_UV >= 3" | bc -l) -eq 1 ]] && echo " → $(give_advice uv_moderate)" )\n\n"

    MESSAGE+="🌌 Astronomy:\n"
    MESSAGE+="🌅 Sunrise: $SUNRISE | 🌇 Sunset: $SUNSET\n"
    MESSAGE+="🌙 Moonrise: $MOONRISE | 🌘 Moonset: $MOONSET\n"
    MESSAGE+="🌔 Moon Phase: $MOON_PHASE\n"

    notify-send -u critical "Weather Update - $CITY" "$MESSAGE"
    echo -e "$MESSAGE"
}

# ------------------------
# Main loop
# ------------------------
main() {
    get_location
    while true; do
        get_weather
        send_notifications
        sleep "$INTERVAL"
    done
}

main
