#!/usr/bin/env bash
# Weather Alarm Script - Human-Advice Version (Fixed & Tweaked)
# Dependencies: curl, jq, bc, notify-send
# Fixes:
# - Corrected wind chill calculation (no ^ in bc, replaced with exp/ln)
# - Portable sunrise/sunset parsing (avoids GNU date-only syntax)
# - Proper AQI mapping (EPA index values clarified)
# - Keeps comfort values (feels-like, humidity, etc.) in "Current" only,
#   NOT as alerts
# - Optional logging to ~/weather_log.txt

API_KEY="98ddb8a158f24a1596882148251309"
BASE_URL="http://api.weatherapi.com/v1"
INTERVAL=1800       # 30 minutes
ALERT_WINDOW=30     # Minutes before astronomical events
LOG_FILE="$HOME/weather_log.txt"

# ------------------------
# Utilities
# ------------------------
deg_to_dir() {
    local deg="$1"
    if ! [[ "$deg" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        echo "Unknown"
        return 1
    fi
    deg=$(echo "($deg + 360) % 360" | bc)
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
        # Replace W^0.16 with exp(0.16*ln(W))
        local W016=$(echo "e(l($W)*0.16)" | bc -l)
        HI=$(echo "scale=2; 13.12 + 0.6215*$T - 11.37*$W016 + 0.3965*$T*$W016" | bc -l)
    fi
    printf "%.1f" "$HI"
}

# ------------------------
# Advice (unchanged from original)
# ------------------------
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
        "pollution_light") echo "Air quality is mostly fine, but sensitive groups may want to limit outdoor activity" ;;
        # Weather phenomena
        "thunderstorm") echo "Thunderstorm, stay indoors" ;;
        "fog") echo "Low visibility, drive carefully" ;;
        "snow") echo "Snowy conditions, dress warmly and drive safely" ;;
        # Astronomy
        "sunrise") echo "Sunrise soon" ;;
        "sunset") echo "Sunset soon" ;;
        "moonrise") echo "Moonrise soon" ;;
        "moonset") echo "Moonset soon" ;;
        "full_moon") echo "Full Moon tonight!" ;;
        "new_moon") echo "New Moon phase." ;;
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

    # Only keep hazard alerts (comfort shown later in Current section)

    # Extreme hot/cold
    (( $(echo "$TEMP_C >= 40" | bc -l) )) && ALERTS+=("🔥 Extreme heat ($TEMP_C°C) → $(give_advice heat_extreme)")
    (( $(echo "$TEMP_C < 0" | bc -l) )) && ALERTS+=("🥶 Extreme cold ($TEMP_C°C) → $(give_advice cold_extreme)")

    # Rain
    (( $(echo "$PRECIP >= 50" | bc -l) )) && ALERTS+=("⛈ Storming ($PRECIP mm) → $(give_advice rain_storm)")
    (( $(echo "$PRECIP >= 20 && $PRECIP < 50" | bc -l) )) && ALERTS+=("🌧 Heavy rain ($PRECIP mm) → $(give_advice rain_heavy)")
    (( $(echo "$PRECIP >= 5 && $PRECIP < 20" | bc -l) )) && ALERTS+=("🌧 Moderate rain ($PRECIP mm) → $(give_advice rain_moderate)")

    # Wind
    (( $(echo "$WIND_KPH >= 80" | bc -l) )) && ALERTS+=("🌪 Storm-force wind ($WIND_KPH km/h) → $(give_advice wind_storm)")
    (( $(echo "$WIND_KPH >= 40 && $WIND_KPH < 80" | bc -l) )) && ALERTS+=("💨 Strong wind ($WIND_KPH km/h) → $(give_advice wind_strong)")

    # UV
    (( $(echo "$UV >= 8" | bc -l) )) && ALERTS+=("🔥 Extreme UV ($UV) → $(give_advice uv_extreme)")
    (( $(echo "$UV >= 6 && $UV < 8" | bc -l) )) && ALERTS+=("😎 High UV ($UV) → $(give_advice uv_high)")

     # Pollution (EPA index 1–6, skip 1 = Good)
    case "$AQI" in
        2) ALERTS+=("🙂 Light pollution (AQI $AQI, PM2.5: $PM25 µg/m³) → $(give_advice pollution_light)") ;;
        3) ALERTS+=("🌫 Moderate pollution (AQI $AQI, PM2.5: $PM25 µg/m³) → $(give_advice pollution_moderate)") ;;
        4) ALERTS+=("☠️ Unhealthy (AQI $AQI, PM2.5: $PM25 µg/m³) → $(give_advice pollution_high)") ;;
        5) ALERTS+=("☠️ Very Unhealthy (AQI $AQI, PM2.5: $PM25 µg/m³) → $(give_advice pollution_very_unhealthy)") ;;
        6) ALERTS+=("☠️☠️ Hazardous (AQI $AQI, PM2.5: $PM25 µg/m³) → $(give_advice pollution_extreme)") ;;
    esac

    # Weather phenomena
    [[ "$CONDITION" =~ [Tt]hunder|[Ll]ightning|[Ss]torm ]] && ALERTS+=("⚡ Thunderstorm detected → $(give_advice thunderstorm)")
    [[ "$CONDITION" =~ [Ff]og ]] && ALERTS+=("🌫 Fog detected → $(give_advice fog)")
    [[ "$CONDITION" =~ [Ss]now ]] && ALERTS+=("❄️ Snow detected → $(give_advice snow)")
}

# ------------------------
# Astronomy alerts (portable)
# ------------------------
generate_astronomy_alerts() {
    local localtime=$(echo "$FORECAST" | jq -r '.location.localtime' | cut -d' ' -f2)
    local hour=${localtime%:*}
    local minute=${localtime#*:}
    local now=$((10#$hour * 60 + 10#$minute))

    # Convert sunrise/sunset with awk instead of GNU date parsing
    local sunrise_minutes=$(echo "$SUNRISE" | awk -F: '{h=$1; m=$2; if(h==12&&$0~/AM/){h=0} else if(h<12&&$0~/PM/){h+=12} sub(/AM|PM/,"",m); print (h*60)+m}')
    local sunset_minutes=$(echo "$SUNSET" | awk -F: '{h=$1; m=$2; if(h==12&&$0~/AM/){h=0} else if(h<12&&$0~/PM/){h+=12} sub(/AM|PM/,"",m); print (h*60)+m}')

    if (( now >= sunrise_minutes - ALERT_WINDOW && now <= sunrise_minutes )); then
        ALERTS+=("🌅 Sunrise soon → $(give_advice sunrise)")
    elif (( now >= sunset_minutes - ALERT_WINDOW && now <= sunset_minutes )); then
        ALERTS+=("🌇 Sunset soon → $(give_advice sunset)")
    fi

    case "$MOON_PHASE" in
        "Full Moon") ALERTS+=("🌕 Full Moon → $(give_advice full_moon)") ;;
        "New Moon") ALERTS+=("🌑 New Moon → $(give_advice new_moon)") ;;
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
    MESSAGE+="• Temp: $TEMP_C°C (Feels: $FEELS°C)\n"
    MESSAGE+="• Humidity: $HUMIDITY%\n"
    MESSAGE+="• Wind: $WIND_KPH km/h ($WIND_DIR)\n"
    MESSAGE+="• Rain: $PRECIP mm\n"
    MESSAGE+="• UV: $UV\n"
    MESSAGE+="• Air Quality: AQI $AQI (PM2.5: $PM25 µg/m³)\n"
    MESSAGE+="• Visibility: $VIS km\n\n"

    MESSAGE+="📅 Forecast:\n"
    LOCAL_HOUR=$(echo "$FORECAST" | jq -r '.location.localtime' | cut -d' ' -f2 | cut -d: -f1)
    for i in {1..3}; do
        idx=$((10#$LOCAL_HOUR + i))
        day=0
        if (( idx > 23 )); then
            idx=$((idx - 24))
            day=1
        fi
        hr_time=$(echo "$FORECAST" | jq -r ".forecast.forecastday[$day].hour[$idx].time" | cut -d' ' -f2)
        hr_temp=$(echo "$FORECAST" | jq -r ".forecast.forecastday[$day].hour[$idx].temp_c")
        hr_rain=$(echo "$FORECAST" | jq -r ".forecast.forecastday[$day].hour[$idx].precip_mm")
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
    echo -e "$MESSAGE" | tee -a "$LOG_FILE"
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
