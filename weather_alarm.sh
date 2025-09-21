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
# - Added missing comfort functions

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
# Unified Weather Assessment System
# ------------------------
assess_weather() {
    local type="$1" value="$2" unit="$3"
    local level advice emoji alert_threshold=0

    case "$type" in
        "temperature")
            if (( $(echo "$value >= 40" | bc -l) )); then
                level="extreme_heat"; advice=$(give_advice heat_extreme); emoji="🔥"; alert_threshold=1
            elif (( $(echo "$value >= 35" | bc -l) )); then
                level="high_heat"; advice=$(give_advice heat_extreme); emoji="🔥"
            elif (( $(echo "$value >= 30" | bc -l) )); then
                level="moderate_heat"; advice=$(give_advice heat_high); emoji="🌡"
            elif (( $(echo "$value >= 25" | bc -l) )); then
                level="mild_heat"; advice=$(give_advice heat_mild); emoji="🌤"
            elif (( $(echo "$value >= 20" | bc -l) )); then
                level="pleasant"; advice=$(give_advice heat_low); emoji="😊"
            elif (( $(echo "$value >= 15" | bc -l) )); then
                level="cool"; advice=$(give_advice cold_low); emoji="🧥"
            elif (( $(echo "$value >= 5" | bc -l) )); then
                level="cold"; advice=$(give_advice cold_mild); emoji="❄️"
            elif (( $(echo "$value >= 0" | bc -l) )); then
                level="very_cold"; advice=$(give_advice cold_high); emoji="🥶"
            else
                level="extreme_cold"; advice=$(give_advice cold_extreme); emoji="🥶"; alert_threshold=1
            fi
            ;;
        "rain")
            if (( $(echo "$value >= 50" | bc -l) )); then
                level="storm"; advice=$(give_advice rain_storm); emoji="⛈"; alert_threshold=1
            elif (( $(echo "$value >= 20" | bc -l) )); then
                level="heavy"; advice=$(give_advice rain_heavy); emoji="🌧"; alert_threshold=1
            elif (( $(echo "$value >= 5" | bc -l) )); then
                level="moderate"; advice=$(give_advice rain_moderate); emoji="🌧"; alert_threshold=1
            elif (( $(echo "$value > 0" | bc -l) )); then
                level="light"; advice=$(give_advice rain_light); emoji="🌦"
            else
                level="none"; advice=$(give_advice rain_none); emoji="☀️"
            fi
            ;;
        "wind")
            if (( $(echo "$value >= 80" | bc -l) )); then
                level="storm"; advice=$(give_advice wind_storm); emoji="🌪"; alert_threshold=1
            elif (( $(echo "$value >= 40" | bc -l) )); then
                level="strong"; advice=$(give_advice wind_strong); emoji="💨"; alert_threshold=1
            elif (( $(echo "$value >= 20" | bc -l) )); then
                level="moderate"; advice=$(give_advice wind_moderate); emoji="💨"
            elif (( $(echo "$value >= 10" | bc -l) )); then
                level="light"; advice=$(give_advice wind_light); emoji="🍃"
            else
                level="calm"; advice=$(give_advice wind_none); emoji="🌀"
            fi
            ;;
        "uv")
            if (( $(echo "$value >= 8" | bc -l) )); then
                level="extreme"; advice=$(give_advice uv_extreme); emoji="🔥"; alert_threshold=1
            elif (( $(echo "$value >= 6" | bc -l) )); then
                level="high"; advice=$(give_advice uv_high); emoji="😎"; alert_threshold=1
            elif (( $(echo "$value >= 3" | bc -l) )); then
                level="moderate"; advice=$(give_advice uv_moderate); emoji="🌞"
            else
                level="low"; advice=$(give_advice uv_low); emoji="🌤"
            fi
            ;;
        "pollution")
            case "$value" in
                1) level="good"; advice="Air quality is good"; emoji="🌿" ;;
                2) level="light"; advice=$(give_advice pollution_light); emoji="🙂" ;;
                3) level="moderate"; advice=$(give_advice pollution_moderate); emoji="🌫" ;;
                4) level="unhealthy"; advice=$(give_advice pollution_high); emoji="☠️"; alert_threshold=1 ;;
                5) level="very_unhealthy"; advice=$(give_advice pollution_very_unhealthy); emoji="☠️"; alert_threshold=1 ;;
                6) level="hazardous"; advice=$(give_advice pollution_extreme); emoji="☠️☠️"; alert_threshold=1 ;;
                *) level="unknown"; advice="Air quality unknown"; emoji="❓" ;;
            esac
            ;;
        "humidity")
            if (( $(echo "$value >= 85" | bc -l) )); then
                level="extreme"; advice=$(give_advice humidity_extreme); emoji="💦"
            elif (( $(echo "$value >= 70" | bc -l) )); then
                level="high"; advice=$(give_advice humidity_high); emoji="💧"
            elif (( $(echo "$value >= 50" | bc -l) )); then
                level="moderate"; advice=$(give_advice humidity_moderate); emoji="💧"
            else
                level="low"; advice=$(give_advice humidity_low); emoji="🏜"
            fi
            ;;
        "visibility")
            if (( $(echo "$value >= 10" | bc -l) )); then
                level="excellent"; advice="Excellent visibility"; emoji="👁"
            elif (( $(echo "$value >= 5" | bc -l) )); then
                level="good"; advice="Good visibility"; emoji="👁"
            elif (( $(echo "$value >= 2" | bc -l) )); then
                level="moderate"; advice="Moderate visibility"; emoji="🌫"
            elif (( $(echo "$value >= 1" | bc -l) )); then
                level="poor"; advice="Poor visibility"; emoji="🌫"
            else
                level="very_poor"; advice="Very poor visibility"; emoji="🌫"
            fi
            ;;
    esac

    # Return format: level|advice|emoji|alert_threshold|value|unit
    echo "$level|$advice|$emoji|$alert_threshold|$value|$unit"
}

# Convenience functions for backward compatibility
comfort_temp() { assess_weather "temperature" "$1" "°C" | cut -d'|' -f2; }
comfort_humidity() { assess_weather "humidity" "$1" "%" | cut -d'|' -f2; }
comfort_wind() { assess_weather "wind" "$1" "km/h" | cut -d'|' -f2; }
comfort_rain() { assess_weather "rain" "$1" "mm" | cut -d'|' -f2; }
comfort_uv() { assess_weather "uv" "$1" "" | cut -d'|' -f2; }
comfort_pollution() { assess_weather "pollution" "$1" "AQI" | cut -d'|' -f2; }
comfort_visibility() { assess_weather "visibility" "$1" "km" | cut -d'|' -f2; }

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

    # Temperature alerts
    temp_result=$(assess_weather "temperature" "$TEMP_C" "°C")
    alert_flag=$(echo "$temp_result" | cut -d'|' -f4)
    if [[ "$alert_flag" == "1" ]]; then
        emoji=$(echo "$temp_result" | cut -d'|' -f3)
        advice=$(echo "$temp_result" | cut -d'|' -f2)
        level=$(echo "$temp_result" | cut -d'|' -f1)
        case "$level" in
            "extreme_heat") ALERTS+=("$emoji Extreme heat ($TEMP_C°C) → $advice") ;;
            "extreme_cold") ALERTS+=("$emoji Extreme cold ($TEMP_C°C) → $advice") ;;
        esac
    fi

    # Rain alerts
    rain_result=$(assess_weather "rain" "$PRECIP" "mm")
    alert_flag=$(echo "$rain_result" | cut -d'|' -f4)
    if [[ "$alert_flag" == "1" ]]; then
        emoji=$(echo "$rain_result" | cut -d'|' -f3)
        advice=$(echo "$rain_result" | cut -d'|' -f2)
        level=$(echo "$rain_result" | cut -d'|' -f1)
        case "$level" in
            "storm") ALERTS+=("$emoji Storming ($PRECIP mm) → $advice") ;;
            "heavy") ALERTS+=("🌧 Heavy rain ($PRECIP mm) → $advice") ;;
            "moderate") ALERTS+=("🌧 Moderate rain ($PRECIP mm) → $advice") ;;
        esac
    fi

    # Wind alerts
    wind_result=$(assess_weather "wind" "$WIND_KPH" "km/h")
    alert_flag=$(echo "$wind_result" | cut -d'|' -f4)
    if [[ "$alert_flag" == "1" ]]; then
        emoji=$(echo "$wind_result" | cut -d'|' -f3)
        advice=$(echo "$wind_result" | cut -d'|' -f2)
        level=$(echo "$wind_result" | cut -d'|' -f1)
        case "$level" in
            "storm") ALERTS+=("🌪 Storm-force wind ($WIND_KPH km/h) → $advice") ;;
            "strong") ALERTS+=("💨 Strong wind ($WIND_KPH km/h) → $advice") ;;
        esac
    fi

    # UV alerts
    uv_result=$(assess_weather "uv" "$UV" "")
    alert_flag=$(echo "$uv_result" | cut -d'|' -f4)
    if [[ "$alert_flag" == "1" ]]; then
        emoji=$(echo "$uv_result" | cut -d'|' -f3)
        advice=$(echo "$uv_result" | cut -d'|' -f2)
        level=$(echo "$uv_result" | cut -d'|' -f1)
        case "$level" in
            "extreme") ALERTS+=("$emoji Extreme UV ($UV) → $advice") ;;
            "high") ALERTS+=("😎 High UV ($UV) → $advice") ;;
        esac
    fi

    # Pollution alerts
    pollution_result=$(assess_weather "pollution" "$AQI" "AQI")
    alert_flag=$(echo "$pollution_result" | cut -d'|' -f4)
    if [[ "$alert_flag" == "1" ]]; then
        emoji=$(echo "$pollution_result" | cut -d'|' -f3)
        advice=$(echo "$pollution_result" | cut -d'|' -f2)
        level=$(echo "$pollution_result" | cut -d'|' -f1)
        case "$level" in
            "unhealthy") ALERTS+=("$emoji Unhealthy (AQI $AQI, PM2.5: $PM25 µg/m³) → $advice") ;;
            "very_unhealthy") ALERTS+=("$emoji Very Unhealthy (AQI $AQI, PM2.5: $PM25 µg/m³) → $advice") ;;
            "hazardous") ALERTS+=("$emoji Hazardous (AQI $AQI, PM2.5: $PM25 µg/m³) → $advice") ;;
        esac
    fi

    # Weather phenomena (unchanged)
    [[ "$CONDITION" =~ [Tt]hunder|[Ll]ightning|[Ss]torm ]] && ALERTS+=("⚡ Thunderstorm detected → $(give_advice thunderstorm)")
    [[ "$CONDITION" =~ [Ff]og ]] && ALERTS+=("🌫 Fog detected → $(give_advice fog)")
    [[ "$CONDITION" =~ [Ss]snow ]] && ALERTS+=("❄️ Snow detected → $(give_advice snow)")
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
    MESSAGE+="• 🌡 Temp: $TEMP_C°C (Feels: $FEELS°C) → $(comfort_temp "$TEMP_C" "$FEELS")\n"
    MESSAGE+="• 💧 Humidity: $HUMIDITY% → $(comfort_humidity "$HUMIDITY")\n"
    MESSAGE+="• 💨 Wind: $WIND_KPH km/h ($WIND_DIR) → $(comfort_wind "$WIND_KPH")\n"
    MESSAGE+="• 🌧 Rain: $PRECIP mm → $(comfort_rain "$PRECIP")\n"
    MESSAGE+="• 🌞 UV: $UV → $(comfort_uv "$UV")\n"
    MESSAGE+="• 🌫 Air Quality: AQI $AQI (PM2.5: $PM25 µg/m³) → $(comfort_pollution "$AQI")\n"
    MESSAGE+="• 👁 Visibility: $VIS km → $(comfort_visibility "$VIS")\n\n"

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
