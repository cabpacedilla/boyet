#!/usr/bin/env bash
# Weather Alarm Script
# Dependencies: curl, jq, bc, notify-send
# Setup: export WEATHER_API_KEY="your_key" in ~/.bashrc

# ------------------------
# Configuration & API Key Management
# ------------------------
if [[ -n "$WEATHER_API_KEY" ]]; then
    API_KEY="$WEATHER_API_KEY"
elif [[ -f "$HOME/.config/weather/api_key" ]]; then
    API_KEY=$(cat "$HOME/.config/weather/api_key" 2>/dev/null | tr -d '\n\r')
elif command -v secret-tool >/dev/null 2>&1; then
    API_KEY=$(secret-tool lookup service weatherapi username "$(whoami)" 2>/dev/null)
else
    echo "Weather API key not found. Please set it using:"
    echo "export WEATHER_API_KEY='your_key_here' in ~/.bashrc"
    exit 1
fi

# Validate API key (check length and alphanumeric characters)
if [[ ${#API_KEY} -ne 30 ]] || [[ ! "$API_KEY" =~ ^[a-zA-Z0-9]+$ ]]; then
    echo "Error: Invalid API key format. WeatherAPI keys should be 32 alphanumeric characters."
    echo "Your key length: ${#API_KEY} characters"
    exit 1
fi

BASE_URL="http://api.weatherapi.com/v1"
INTERVAL=1800
ALERT_WINDOW=30
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

check_api_response() {
    local response="$1"
    local endpoint="$2"

    if [[ -z "$response" ]]; then
        echo "Error: Empty response from $endpoint API"
        return 1
    fi

    local error=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
    if [[ -n "$error" ]]; then
        case "$error" in
            *"API key"*|*"Invalid key"*)
                echo "Error: Invalid API key. Please check your WeatherAPI key."
                exit 1 ;;
            *"exceed"*|*"limit"*)
                echo "Error: API rate limit exceeded."
                return 1 ;;
            *"Invalid location"*)
                echo "Error: Invalid location detected."
                return 1 ;;
            *)
                echo "API Error: $error"
                return 1 ;;
        esac
    fi

    return 0
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

    echo "$level|$advice|$emoji|$alert_threshold|$value|$unit"
}

comfort_temp() { assess_weather "temperature" "$1" "°C" | cut -d'|' -f2; }
comfort_humidity() { assess_weather "humidity" "$1" "%" | cut -d'|' -f2; }
comfort_wind() { assess_weather "wind" "$1" "km/h" | cut -d'|' -f2; }
comfort_rain() { assess_weather "rain" "$1" "mm" | cut -d'|' -f2; }
comfort_uv() { assess_weather "uv" "$1" "" | cut -d'|' -f2; }
comfort_pollution() { assess_weather "pollution" "$1" "AQI" | cut -d'|' -f2; }
comfort_visibility() { assess_weather "visibility" "$1" "km" | cut -d'|' -f2; }

give_advice() {
    case "$1" in
        "heat_extreme") echo "Stay indoors, hydrate" ;;
        "heat_high") echo "Avoid sun, drink water" ;;
        "heat_mild") echo "Stay hydrated" ;;
        "heat_low") echo "Pleasant weather" ;;
        "cold_extreme") echo "Layer up, limit outdoors" ;;
        "cold_high") echo "Heavy coat needed" ;;
        "cold_mild") echo "Light jacket recommended" ;;
        "cold_low") echo "Dress comfortably" ;;
        "humidity_extreme") echo "Use AC/dehumidifier" ;;
        "humidity_high") echo "Stay cool" ;;
        "humidity_moderate") echo "Slightly heavy air" ;;
        "humidity_low") echo "Dry air" ;;
        "rain_storm") echo "Seek shelter" ;;
        "rain_heavy") echo "Stay indoors" ;;
        "rain_moderate") echo "Umbrella needed" ;;
        "rain_light") echo "Light drizzle" ;;
        "rain_none") echo "No rain" ;;
        "wind_storm") echo "Stay indoors" ;;
        "wind_strong") echo "Secure items" ;;
        "wind_moderate") echo "Steady breeze" ;;
        "wind_light") echo "Gentle breeze" ;;
        "wind_none") echo "Calm" ;;
        "uv_extreme") echo "Stay in shade" ;;
        "uv_high") echo "Sunscreen + hat" ;;
        "uv_moderate") echo "Use sunscreen" ;;
        "uv_low") echo "Safe sun exposure" ;;
        "pollution_extreme") echo "Stay indoors" ;;
        "pollution_very_unhealthy") echo "Avoid outdoors" ;;
        "pollution_high") echo "Limit exposure" ;;
        "pollution_moderate") echo "Use caution" ;;
        "pollution_light") echo "Mostly fine air" ;;
        "thunderstorm") echo "Stay inside" ;;
        "fog") echo "Drive carefully" ;;
        "snow") echo "Dress warm" ;;
        "sunrise") echo "Start your day fresh" ;;
		"sunset") echo "Relax and enjoy the evening" ;;
		"moonrise") echo "Look up at the rising Moon" ;;
		"moonset") echo "Catch the Moon before it sets" ;;
		"full_moon") echo "Perfect night for stargazing" ;;
		"new_moon") echo "Ideal time to spot faint stars" ;;
		"first_quarter") echo "Half-lit Moon in the sky" ;;
		"last_quarter") echo "Waning Moon for night observation" ;;
		"eclipse") echo "Don't miss this celestial event" ;;
        *) echo "" ;;
    esac
}

# ------------------------
# Location detection
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
    FORECAST=$(curl -s --connect-timeout 10 --max-time 30 "$BASE_URL/forecast.json?key=$API_KEY&q=$LAT,$LON&days=2&aqi=yes&alerts=yes")
    if ! check_api_response "$FORECAST" "forecast"; then
        echo "Failed to fetch weather data. Retrying in 5 minutes..."
        sleep 300
        return 1
    fi

    ASTRONOMY=$(curl -s --connect-timeout 10 --max-time 30 "$BASE_URL/astronomy.json?key=$API_KEY&q=$LAT,$LON")
    if ! check_api_response "$ASTRONOMY" "astronomy"; then
        echo "Warning: Failed to fetch astronomy data. Continuing with weather only..."
        ASTRONOMY='{"astronomy":{"astro":{"sunrise":"","sunset":"","moonrise":"","moonset":"","moon_phase":""}}}'
    fi

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

    return 0
}

# ------------------------
# Generate alerts
# ------------------------
generate_alerts() {
    ALERTS=()

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

    [[ "$CONDITION" =~ [Tt]hunder|[Ll]ightning|[Ss]torm ]] && ALERTS+=("⚡ Thunderstorm detected → $(give_advice thunderstorm)")
    [[ "$CONDITION" =~ [Ff]og ]] && ALERTS+=("🌫 Fog detected → $(give_advice fog)")
    [[ "$CONDITION" =~ [Ss]now ]] && ALERTS+=("❄️ Snow detected → $(give_advice snow)")
}

# ------------------------
# Astronomy alerts
# ------------------------
generate_astronomy_alerts() {
    local localtime=$(echo "$FORECAST" | jq -r '.location.localtime' | cut -d' ' -f2)
    local hour=${localtime%:*}
    local minute=${localtime#*:}
    local now=$((10#$hour * 60 + 10#$minute))

    local sunrise_minutes=$(echo "$SUNRISE" | awk -F: '{h=$1; m=$2; if(h==12&&$0~/AM/){h=0} else if(h<12&&$0~/PM/){h+=12} sub(/AM|PM/,"",m); print (h*60)+m}')
    local sunset_minutes=$(echo "$SUNSET" | awk -F: '{h=$1; m=$2; if(h==12&&$0~/AM/){h=0} else if(h<12&&$0~/PM/){h+=12} sub(/AM|PM/,"",m); print (h*60)+m}')

    # Moonrise and moonset in minutes
    local moonrise_minutes=$(echo "$MOONRISE" | awk -F: '{h=$1; m=$2; if(h==12&&$0~/AM/){h=0} else if(h<12&&$0~/PM/){h+=12} sub(/AM|PM/,"",m); print (h*60)+m}')
    local moonset_minutes=$(echo "$MOONSET" | awk -F: '{h=$1; m=$2; if(h==12&&$0~/AM/){h=0} else if(h<12&&$0~/PM/){h+=12} sub(/AM|PM/,"",m); print (h*60)+m}')

    # Sunrise/Sunset alerts
    if (( now >= sunrise_minutes - ALERT_WINDOW && now <= sunrise_minutes )); then
        ALERTS+=("Sunrise soon → $(give_advice sunrise)")
    elif (( now >= sunset_minutes - ALERT_WINDOW && now <= sunset_minutes )); then
        ALERTS+=("Sunset soon → $(give_advice sunset)")
    fi

    # Moonrise/Moonset alerts
    if (( now >= moonrise_minutes - ALERT_WINDOW && now <= moonrise_minutes )); then
        ALERTS+=("Moonrise soon → $(give_advice moonrise)")
    elif (( now >= moonset_minutes - ALERT_WINDOW && now <= moonset_minutes )); then
        ALERTS+=("Moonset soon → $(give_advice moonset)")
    fi

    case "$MOON_PHASE" in
        "Full Moon") ALERTS+=("Full Moon → $(give_advice full_moon)") ;;
		"New Moon") ALERTS+=("New Moon → $(give_advice new_moon)") ;;
		"Eclipse") ALERTS+=("Eclipse today → $(give_advice eclipse)") ;;
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
    MESSAGE+="🌡 High: $MAX_TEMP°C, Low: $MIN_TEMP°C\n"
    MESSAGE+="🌞 Peak UV: $PEAK_UV$( [[ $(echo "$PEAK_UV >= 3" | bc -l) -eq 1 ]] && echo " → $(give_advice uv_moderate)" )\n\n"

    MESSAGE+="🌌 Astronomy:\n"
    MESSAGE+="🌅 Sunrise: $SUNRISE | 🌇 Sunset: $SUNSET\n"
    MESSAGE+="🌙 Moonrise: $MOONRISE | 🌘 Moonset: $MOONSET\n"
    MESSAGE+="🌔 Moon Phase: $MOON_PHASE\n"

    notify-send -u critical "Weather Update - $CITY ($(date +%-I:%M))" "$MESSAGE"
    echo -e "$MESSAGE" | tee -a "$LOG_FILE"
}

# ------------------------
# Main loop
# ------------------------
main() {
    get_location

    if [[ -z "$LAT" ]] || [[ -z "$LON" ]] || [[ "$LAT" == "null" ]] || [[ "$LON" == "null" ]]; then
        echo "Error: Could not determine location. Please check your internet connection."
        exit 1
    fi

    echo "Starting weather monitoring for $CITY ($LAT,$LON)"
    echo "API calls every $((INTERVAL/60)) minutes. Logs saved to: $LOG_FILE"

    while true; do
        if get_weather; then
            send_notifications
            echo "$(date): Weather update sent successfully"
        else
            echo "$(date): Weather update failed, will retry next cycle"
        fi
        sleep "$INTERVAL"
    done
}

if [[ "$1" == "--setup" ]]; then
    echo "API key should be set in ~/.bashrc as: export WEATHER_API_KEY='your_key_here'"
    exit 0
fi

main
