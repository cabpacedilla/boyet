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

# Convert time string to minutes since midnight (handles both 12h and 24h formats)
time_to_minutes() {
    local time_str="$1"
    local hour minute
    
    # Handle empty or invalid input
    [[ -z "$time_str" ]] && { echo "0"; return 1; }
    
    # Check if it's 24-hour format (no AM/PM)
    if [[ ! "$time_str" =~ (AM|PM|am|pm) ]]; then
        # 24-hour format: HH:MM
        hour=$(echo "$time_str" | cut -d: -f1 | tr -d ' ')
        minute=$(echo "$time_str" | cut -d: -f2 | tr -d ' ')
        
        # Validate hour and minute
        [[ ! "$hour" =~ ^[0-9]+$ ]] && { echo "0"; return 1; }
        [[ ! "$minute" =~ ^[0-9]+$ ]] && { echo "0"; return 1; }
        [[ $hour -gt 23 ]] && { echo "0"; return 1; }
        [[ $minute -gt 59 ]] && { echo "0"; return 1; }
        
        echo $((10#$hour * 60 + 10#$minute))
        return 0
    fi
    
    # 12-hour format: H:MM AM/PM
    hour=$(echo "$time_str" | cut -d: -f1 | tr -d ' ')
    minute=$(echo "$time_str" | cut -d: -f2 | sed 's/[^0-9]//g')
    
    # Validate components
    [[ ! "$hour" =~ ^[0-9]+$ ]] && { echo "0"; return 1; }
    [[ ! "$minute" =~ ^[0-9]+$ ]] && { echo "0"; return 1; }
    [[ $hour -gt 12 || $hour -lt 1 ]] && { echo "0"; return 1; }
    [[ $minute -gt 59 ]] && { echo "0"; return 1; }
    
    # Convert to 24-hour format
    if [[ "$time_str" =~ (AM|am) ]]; then
        [[ $hour -eq 12 ]] && hour=0
    elif [[ "$time_str" =~ (PM|pm) ]]; then
        [[ $hour -ne 12 ]] && hour=$((hour + 12))
    fi
    
    echo $((hour * 60 + 10#$minute))
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
# Advice System
# ------------------------
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
                level="high_heat"; advice=$(give_advice heat_high); emoji="🔥"
            elif (( $(echo "$value >= 30" | bc -l) )); then
                level="moderate_heat"; advice=$(give_advice heat_mild); emoji="🌡"
            elif (( $(echo "$value >= 25" | bc -l) )); then
                level="mild_heat"; advice=$(give_advice heat_low); emoji="🌤"
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

# ------------------------
# Simplified Assessment Functions
# ------------------------
get_advice() {
    local assessment=$(assess_weather "$1" "$2" "$3")
    echo "$assessment" | cut -d'|' -f2
}

get_alert_status() {
    local assessment=$(assess_weather "$1" "$2" "$3")
    echo "$assessment" | cut -d'|' -f4
}

get_emoji() {
    local assessment=$(assess_weather "$1" "$2" "$3")
    echo "$assessment" | cut -d'|' -f3
}

get_level() {
    local assessment=$(assess_weather "$1" "$2" "$3")
    echo "$assessment" | cut -d'|' -f1
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

    # Temperature alerts
    if [[ "$(get_alert_status temperature "$TEMP_C")" == "1" ]]; then
        emoji=$(get_emoji temperature "$TEMP_C")
        advice=$(get_advice temperature "$TEMP_C")
        level=$(get_level temperature "$TEMP_C")
        case "$level" in
            "extreme_heat") ALERTS+=("$emoji Extreme heat ($TEMP_C°C) → $advice") ;;
            "extreme_cold") ALERTS+=("$emoji Extreme cold ($TEMP_C°C) → $advice") ;;
        esac
    fi

    # Rain alerts
    if [[ "$(get_alert_status rain "$PRECIP")" == "1" ]]; then
        emoji=$(get_emoji rain "$PRECIP")
        advice=$(get_advice rain "$PRECIP")
        level=$(get_level rain "$PRECIP")
        case "$level" in
            "storm") ALERTS+=("$emoji Storming ($PRECIP mm) → $advice") ;;
            "heavy") ALERTS+=("🌧 Heavy rain ($PRECIP mm) → $advice") ;;
            "moderate") ALERTS+=("🌧 Moderate rain ($PRECIP mm) → $advice") ;;
        esac
    fi

    # Wind alerts
    if [[ "$(get_alert_status wind "$WIND_KPH")" == "1" ]]; then
        emoji=$(get_emoji wind "$WIND_KPH")
        advice=$(get_advice wind "$WIND_KPH")
        level=$(get_level wind "$WIND_KPH")
        case "$level" in
            "storm") ALERTS+=("🌪 Storm-force wind ($WIND_KPH km/h) → $advice") ;;
            "strong") ALERTS+=("💨 Strong wind ($WIND_KPH km/h) → $advice") ;;
        esac
    fi

    # UV alerts
    if [[ "$(get_alert_status uv "$UV")" == "1" ]]; then
        emoji=$(get_emoji uv "$UV")
        advice=$(get_advice uv "$UV")
        level=$(get_level uv "$UV")
        case "$level" in
            "extreme") ALERTS+=("$emoji Extreme UV ($UV) → $advice") ;;
            "high") ALERTS+=("😎 High UV ($UV) → $advice") ;;
        esac
    fi

    # Pollution alerts
    if [[ "$(get_alert_status pollution "$AQI")" == "1" ]]; then
        emoji=$(get_emoji pollution "$AQI")
        advice=$(get_advice pollution "$AQI")
        level=$(get_level pollution "$AQI")
        case "$level" in
            "unhealthy") ALERTS+=("$emoji Unhealthy (AQI $AQI, PM2.5: $PM25 µg/m³) → $advice") ;;
            "very_unhealthy") ALERTS+=("$emoji Very Unhealthy (AQI $AQI, PM2.5: $PM25 µg/m³) → $advice") ;;
            "hazardous") ALERTS+=("$emoji Hazardous (AQI $AQI, PM2.5: $PM25 µg/m³) → $advice") ;;
        esac
    fi

    # Condition-based alerts
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

    local sunrise_minutes=$(time_to_minutes "$SUNRISE")
    local sunset_minutes=$(time_to_minutes "$SUNSET")
    
    # Moonrise and moonset in minutes
    local moonrise_minutes=$(time_to_minutes "$MOONRISE")
    local moonset_minutes=$(time_to_minutes "$MOONSET")

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
    MESSAGE+="• 🌡 Temp: $TEMP_C°C (Feels: $FEELS°C) → $(get_advice temperature "$TEMP_C")\n"
    MESSAGE+="• 💧 Humidity: $HUMIDITY% → $(get_advice humidity "$HUMIDITY")\n"
    MESSAGE+="• 💨 Wind: $WIND_KPH km/h ($WIND_DIR) → $(get_advice wind "$WIND_KPH")\n"
    MESSAGE+="• 🌧 Rain: $PRECIP mm → $(get_advice rain "$PRECIP")\n"
    MESSAGE+="• 🌞 UV: $UV → $(get_advice uv "$UV")\n"
    MESSAGE+="• 🌫 Air Quality: AQI $AQI (PM2.5: $PM25 µg/m³) → $(get_advice pollution "$AQI")\n"
    MESSAGE+="• 👁 Visibility: $VIS km → $(get_advice visibility "$VIS")\n\n"

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
        
        # Use unified assessment system for rain advice
        hr_advice=$(get_advice rain "$hr_rain")
        
        MESSAGE+="• $hr_time → $hr_temp°C, $hr_rain mm"
        [[ -n "$hr_advice" ]] && MESSAGE+=" → $hr_advice"
        MESSAGE+="\n"
    done
    MESSAGE+="🌡 High: $MAX_TEMP°C, Low: $MIN_TEMP°C\n"
    
    # Use unified assessment for peak UV
    peak_uv_advice=$(get_advice uv "$PEAK_UV")
    MESSAGE+="🌞 Peak UV: $PEAK_UV"
    [[ "$peak_uv_advice" != "Safe sun exposure" ]] && MESSAGE+=" → $peak_uv_advice"
    MESSAGE+="\n\n"

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
