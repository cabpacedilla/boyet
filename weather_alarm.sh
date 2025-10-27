#!/usr/bin/env bash
# Weather Alarm Script (enhanced multi‑day peaks) - FIXED VERSION
# Dependencies: curl, jq, bc, notify-send
# Setup: export WEATHER_API_KEY="your_key" in ~/.bashrc

# ------------------------
# Configuration & API Key Management
# ------------------------
if [[ -n "$WEATHER_API_KEY" ]]; then
    API_KEY="$WEATHER_API_KEY"
elif [[ -f "$HOME/.config/weather/api_key" ]]; then
    API_KEY=$(cat "$HOME/.config/weather/api_key" 2>/dev/null | tr -d '\n\r')
elif command -v secret‑tool >/dev/null 2>&1; then
    API_KEY=$(secret‑tool lookup service weatherapi username "$(whoami)" 2>/dev/null)
else
    echo "Weather API key not found. Please set it using:"
    echo "export WEATHER_API_KEY='your_key_here' in ~/.bashrc"
    exit 1
fi

# Validate API key (simple check)
if [[ ${#API_KEY} -lt 20 ]]; then
    echo "Warning: API key seems too short; double check it."
fi

BASE_URL="http://api.weatherapi.com/v1"
INTERVAL=1800
ALERT_WINDOW=30
LOG_FILE="$HOME/weather_log.txt"
CURL_DELAY=1

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

time_to_minutes() {
    local time_str="$1"
    local hour minute

    [[ -z "$time_str" ]] && { echo "0"; return 1; }

    if [[ ! "$time_str" =~ (AM|PM|am|pm) ]]; then
        hour=$(echo "$time_str" | cut -d: -f1 | tr -d ' ')
        minute=$(echo "$time_str" | cut -d: -f2 | tr -d ' ')
        [[ ! "$hour" =~ ^[0-9]+$ ]] && { echo "0"; return 1; }
        [[ ! "$minute" =~ ^[0-9]+$ ]] && { echo "0"; return 1; }
        [[ $hour -gt 23 ]] && { echo "0"; return 1; }
        [[ $minute -gt 59 ]] && { echo "0"; return 1; }
        echo $((10#$hour * 60 + 10#$minute))
        return 0
    fi

    hour=$(echo "$time_str" | cut -d: -f1 | tr -d ' ')
    minute=$(echo "$time_str" | cut -d: -f2 | sed 's/[^0-9]//g')
    [[ ! "$hour" =~ ^[0-9]+$ ]] && { echo "0"; return 1; }
    [[ ! "$minute" =~ ^[0-9]+$ ]] && { echo "0"; return 1; }
    [[ $hour -gt 12 || $hour -lt 1 ]] && { echo "0"; return 1; }
    [[ $minute -gt 59 ]] && { echo "0"; return 1; }

    if [[ "$time_str" =~ (AM|am) ]]; then
        [[ $hour -eq 12 ]] && hour=0
    elif [[ "$time_str" =~ (PM|pm) ]]; then
        [[ $hour -ne 12 ]] && hour=$((hour + 12))
    fi

    echo $((hour * 60 + 10#$minute))
}

# Convert 24-hour time to 12-hour format with AM/PM
format_time_12hr() {
    local time_24hr="$1"
    local hour minute ampm
    
    # Extract hour and minute
    hour=$(echo "$time_24hr" | cut -d: -f1)
    minute=$(echo "$time_24hr" | cut -d: -f2)
    
    # Remove leading zeros from hour
    hour=$((10#$hour))
    
    # Determine AM/PM and convert hour
    if [[ $hour -eq 0 ]]; then
        hour=12
        ampm="AM"
    elif [[ $hour -eq 12 ]]; then
        ampm="PM"
    elif [[ $hour -gt 12 ]]; then
        hour=$((hour - 12))
        ampm="PM"
    else
        ampm="AM"
    fi
    
    # Format minute with leading zero if needed
    minute=$(printf "%02d" $minute)
    
    echo "${hour}:${minute} $ampm"
}

check_api_response() {
    local response="$1"
    local endpoint="$2"

    if [[ -z "$response" ]]; then
        echo "Error: Empty response from $endpoint API"
        return 1
    fi

    # Check if response is valid JSON
    if ! echo "$response" | jq -e . >/dev/null 2>&1; then
        echo "Error: Invalid JSON response from $endpoint API"
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
# Advice System (with pressure in inHg)
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
        "pressure_very_high") echo "Very high - clear" ;;
        "pressure_high") echo "High - fair" ;;
        "pressure_normal") echo "Normal - typical" ;;
        "pressure_low") echo "Low - rain likely" ;;
        "pressure_very_low") echo "Very low - storms" ;;
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
                level="light"; advice=$(give_advice rain_light); emoji="🌦"; alert_threshold=1
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
        "pressure")
            # Atmospheric pressure in inches of mercury (inHg) - FIXED thresholds
            if (( $(echo "$value >= 30.2" | bc -l) )); then
                level="very_high"; advice=$(give_advice pressure_very_high); emoji="🔵"
            elif (( $(echo "$value >= 29.9" | bc -l) )); then
                level="high"; advice=$(give_advice pressure_high); emoji="🔷"
            elif (( $(echo "$value >= 29.5" | bc -l) )); then
                level="normal"; advice=$(give_advice pressure_normal); emoji="🌤"
            elif (( $(echo "$value >= 29.0" | bc -l) )); then
                level="low"; advice=$(give_advice pressure_low); emoji="🌧"; alert_threshold=1
            else
                level="very_low"; advice=$(give_advice pressure_very_low); emoji="⛈"; alert_threshold=1
            fi
            ;;
    esac

    echo "$level|$advice|$emoji|$alert_threshold|$value|$unit"
}

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
    LOC=$(curl -s --connect-timeout 10 ipinfo.io/loc 2>/dev/null)
    sleep "$CURL_DELAY"
    [[ -z "$LOC" ]] && LOC=$(curl -s --connect-timeout 10 ipapi.co/latlong 2>/dev/null)
    sleep "$CURL_DELAY"
    [[ -z "$LOC" ]] && LOC=$(curl -s --connect-timeout 10 ifconfig.me 2>/dev/null)
    sleep "$CURL_DELAY"
    LAT=$(echo "$LOC" | cut -d, -f1)
    LON=$(echo "$LOC" | cut -d, -f2)
    CITY=$(curl -s --connect-timeout 10 "https://nominatim.openstreetmap.org/reverse?lat=$LAT&lon=$LON&format=json" \
        | jq -r '.address.city // .address.town // .address.village // .address.hamlet // "Unknown"' 2>/dev/null)
    sleep "$CURL_DELAY"
    echo "Location detected: $CITY ($LAT,$LON)"
}

# ------------------------
# Fetch weather data (forecast + astronomy)
# ------------------------
get_weather() {
    FORECAST=$(curl -s --connect-timeout 10 --max-time 30 \
        "$BASE_URL/forecast.json?key=$API_KEY&q=$LAT,$LON&days=2&aqi=yes&alerts=yes")
    sleep "$CURL_DELAY"
    if ! check_api_response "$FORECAST" "forecast"; then
        echo "Failed to fetch weather data. Retrying in 5 minutes..."
        sleep 300
        return 1
    fi

    ASTRONOMY=$(curl -s --connect-timeout 10 --max-time 30 \
        "$BASE_URL/astronomy.json?key=$API_KEY&q=$LAT,$LON")
    sleep "$CURL_DELAY"
    if ! check_api_response "$ASTRONOMY" "astronomy"; then
        echo "Warning: Failed to fetch astronomy data. Continuing with weather only..."
        ASTRONOMY='{"astronomy":{"astro":{"sunrise":"","sunset":"","moonrise":"","moonset":"","moon_phase":""}}}'
    fi

    # Current conditions with fallbacks
    TEMP_C=$(echo "$FORECAST" | jq -r '.current.temp_c // 0')
    FEELS=$(echo "$FORECAST" | jq -r '.current.feelslike_c // 0')
    HUMIDITY=$(echo "$FORECAST" | jq -r '.current.humidity // 0')
    WIND_KPH=$(echo "$FORECAST" | jq -r '.current.wind_kph // 0')
    WIND_DIR_DEG=$(echo "$FORECAST" | jq -r '.current.wind_degree // 0')
    WIND_DIR=$(deg_to_dir "$WIND_DIR_DEG")
    PRECIP=$(echo "$FORECAST" | jq -r '.current.precip_mm // 0')
    UV=$(echo "$FORECAST" | jq -r '.current.uv // 0')
    VIS=$(echo "$FORECAST" | jq -r '.current.vis_km // 0')
    PRESSURE_MB=$(echo "$FORECAST" | jq -r '.current.pressure_mb // 0')
    PRESSURE_IN=$(echo "$FORECAST" | jq -r '.current.pressure_in // 0')
    CONDITION=$(echo "$FORECAST" | jq -r '.current.condition.text // ""')
    AQI=$(echo "$FORECAST" | jq -r '.current.air_quality["us-epa-index"] // 0')
    PM25=$(echo "$FORECAST" | jq -r '.current.air_quality.pm2_5 // 0')

    SUNRISE=$(echo "$ASTRONOMY" | jq -r '.astronomy.astro.sunrise // ""')
    SUNSET=$(echo "$ASTRONOMY" | jq -r '.astronomy.astro.sunset // ""')
    MOONRISE=$(echo "$ASTRONOMY" | jq -r '.astronomy.astro.moonrise // ""')
    MOONSET=$(echo "$ASTRONOMY" | jq -r '.astronomy.astro.moonset // ""')
    MOON_PHASE=$(echo "$ASTRONOMY" | jq -r '.astronomy.astro.moon_phase // ""')

    return 0
}

# ------------------------
# Improved data extraction functions
# ------------------------
extract_peak_data() {
    local forecast_json="$1"
    local day_index="$2"
    
    # Extract max temperature with time
    local max_temp_data=$(echo "$forecast_json" | jq -r ".forecast.forecastday[$day_index].hour | max_by(.temp_c) | {time: .time, value: .temp_c}" 2>/dev/null)
    local max_temp_value=$(echo "$max_temp_data" | jq -r '.value // 0')
    local max_temp_time=$(echo "$max_temp_data" | jq -r '.time // ""' | cut -d' ' -f2)
    
    # Extract min temperature with time
    local min_temp_data=$(echo "$forecast_json" | jq -r ".forecast.forecastday[$day_index].hour | min_by(.temp_c) | {time: .time, value: .temp_c}" 2>/dev/null)
    local min_temp_value=$(echo "$min_temp_data" | jq -r '.value // 0')
    local min_temp_time=$(echo "$min_temp_data" | jq -r '.time // ""' | cut -d' ' -f2)
    
    # Extract peak UV with time - FIXED: handle empty results
    local uv_data=$(echo "$forecast_json" | jq -r ".forecast.forecastday[$day_index].hour | map(select(.uv != null)) | max_by(.uv) | {time: .time, value: .uv} // \"\"" 2>/dev/null)
    local peak_uv_value="0"
    local uv_hour="Unknown"
    
    if [[ -n "$uv_data" ]] && [[ "$uv_data" != "null" ]]; then
        peak_uv_value=$(echo "$uv_data" | jq -r '.value // 0')
        local uv_time=$(echo "$uv_data" | jq -r '.time // ""')
        [[ -n "$uv_time" ]] && uv_hour=$(echo "$uv_time" | cut -d' ' -f2)
    fi
    
    # Extract peak rain with time
    local rain_data=$(echo "$forecast_json" | jq -r ".forecast.forecastday[$day_index].hour | max_by(.precip_mm) | {time: .time, value: .precip_mm}" 2>/dev/null)
    local rain_peak=$(echo "$rain_data" | jq -r '.value // 0')
    local rain_time=$(echo "$rain_data" | jq -r '.time // ""' | cut -d' ' -f2)
    
    # Convert times to 12-hour format
    [[ -n "$max_temp_time" ]] && max_temp_time=$(format_time_12hr "$max_temp_time")
    [[ -n "$min_temp_time" ]] && min_temp_time=$(format_time_12hr "$min_temp_time")
    [[ -n "$uv_hour" && "$uv_hour" != "Unknown" ]] && uv_hour=$(format_time_12hr "$uv_hour")
    [[ -n "$rain_time" ]] && rain_time=$(format_time_12hr "$rain_time")
    
    # Get advice and emojis
    local temp_advice=$(get_advice temperature "$max_temp_value")
    local temp_emoji=$(get_emoji temperature "$max_temp_value")
    local rain_advice=$(get_advice rain "$rain_peak")
    local rain_emoji=$(get_emoji rain "$rain_peak")
    local uv_advice=$(get_advice uv "$peak_uv_value")
    local uv_emoji=$(get_emoji uv "$peak_uv_value")
    
    echo "$max_temp_value|$max_temp_time|$min_temp_value|$min_temp_time|$peak_uv_value|$uv_hour|$rain_peak|$rain_time|$temp_advice|$temp_emoji|$rain_advice|$rain_emoji|$uv_advice|$uv_emoji"
}

# ------------------------
# Generate alerts & notifications (with emojis)
# ------------------------
generate_alerts() {
    ALERTS=()

    if [[ "$(get_alert_status temperature "$TEMP_C")" == "1" ]]; then
        emoji=$(get_emoji temperature "$TEMP_C")
        advice=$(get_advice temperature "$TEMP_C")
        level=$(get_level temperature "$TEMP_C")
        case "$level" in
            "extreme_heat") ALERTS+=("$emoji Extreme heat ($TEMP_C°C) → $advice") ;;
            "extreme_cold") ALERTS+=("$emoji Extreme cold ($TEMP_C°C) → $advice") ;;
        esac
    fi

    if [[ "$(get_alert_status rain "$PRECIP")" == "1" ]]; then
        emoji=$(get_emoji rain "$PRECIP")
        advice=$(get_advice rain "$PRECIP")
        level=$(get_level rain "$PRECIP")
        case "$level" in
            "storm") ALERTS+=("$emoji Storming ($PRECIP mm) → $advice") ;;
            "heavy") ALERTS+=("$emoji Heavy rain ($PRECIP mm) → $advice") ;;
            "moderate") ALERTS+=("$emoji Moderate rain ($PRECIP mm) → $advice") ;;
            "light") ALERTS+=("$emoji Light rain ($PRECIP mm) → $advice") ;;
        esac
    fi

    if [[ "$(get_alert_status wind "$WIND_KPH")" == "1" ]]; then
        emoji=$(get_emoji wind "$WIND_KPH")
        advice=$(get_advice wind "$WIND_KPH")
        level=$(get_level wind "$WIND_KPH")
        case "$level" in
            "storm") ALERTS+=("$emoji Storm-force wind ($WIND_KPH km/h) → $advice") ;;
            "strong") ALERTS+=("$emoji Strong wind ($WIND_KPH km/h) → $advice") ;;
        esac
    fi

    if [[ "$(get_alert_status uv "$UV")" == "1" ]]; then
        emoji=$(get_emoji uv "$UV")
        advice=$(get_advice uv "$UV")
        level=$(get_level uv "$UV")
        case "$level" in
            "extreme") ALERTS+=("$emoji Extreme UV ($UV) → $advice") ;;
            "high") ALERTS+=("$emoji High UV ($UV) → $advice") ;;
        esac
    fi

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

    # Pressure alerts (using inHg)
    if [[ "$(get_alert_status pressure "$PRESSURE_IN")" == "1" ]]; then
        emoji=$(get_emoji pressure "$PRESSURE_IN")
        advice=$(get_advice pressure "$PRESSURE_IN")
        level=$(get_level pressure "$PRESSURE_IN")
        case "$level" in
            "very_low") ALERTS+=("$emoji Very low pressure ($PRESSURE_IN inHg) → $advice") ;;
            "low") ALERTS+=("$emoji Low pressure ($PRESSURE_IN inHg) → $advice") ;;
        esac
    fi

    [[ "$CONDITION" =~ [Tt]hunder|[Ll]ightning|[Ss]torm ]] && ALERTS+=("⚡ Thunderstorm detected → $(give_advice thunderstorm)")
    [[ "$CONDITION" =~ [Ff]og ]] && ALERTS+=("🌫 Fog detected → $(give_advice fog)")
    [[ "$CONDITION" =~ [Ss]now ]] && ALERTS+=("❄️ Snow detected → $(give_advice snow)")
}

generate_astronomy_alerts() {
    local localtime=$(echo "$FORECAST" | jq -r '.location.localtime' | cut -d' ' -f2)
    local hour=${localtime%:*}
    local minute=${localtime#*:}
    local now=$((10#$hour * 60 + 10#$minute))

    local sunrise_minutes=$(time_to_minutes "$SUNRISE")
    local sunset_minutes=$(time_to_minutes "$SUNSET")
    local moonrise_minutes=$(time_to_minutes "$MOONRISE")
    local moonset_minutes=$(time_to_minutes "$MOONSET")

    if (( now >= sunrise_minutes - ALERT_WINDOW && now <= sunrise_minutes )); then
        ALERTS+=("☀️ Sunrise at $SUNRISE → $(give_advice sunrise)")
    elif (( now >= sunset_minutes - ALERT_WINDOW && now <= sunset_minutes )); then
        ALERTS+=("🌇 Sunset at $SUNSET → $(give_advice sunset)")
    fi

    if (( now >= moonrise_minutes - ALERT_WINDOW && now <= moonrise_minutes )); then
        ALERTS+=("🌙 Moonrise at $MOONRISE → $(give_advice moonrise)")
    elif (( now >= moonset_minutes - ALERT_WINDOW && now <= moonset_minutes )); then
        ALERTS+=("🌘 Moonset at $MOONSET → $(give_advice moonset)")
    fi

    case "$MOON_PHASE" in
        "Full Moon") ALERTS+=("🌕 Full Moon → $(give_advice full_moon)") ;;
        "New Moon") ALERTS+=("🌑 New Moon → $(give_advice new_moon)") ;;
        "Eclipse") ALERTS+=("🌒 Eclipse today → $(give_advice eclipse)") ;;
    esac
}

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

    MESSAGE+="📊 Current ($CITY: $LAT, $LON):\n"
    MESSAGE+="• 🌡 Temp: $TEMP_C°C (Feels: $FEELS°C) → $(get_advice temperature "$TEMP_C") $(get_emoji temperature "$TEMP_C")\n"
    MESSAGE+="• 💧 Humidity: $HUMIDITY% → $(get_advice humidity "$HUMIDITY") $(get_emoji humidity "$HUMIDITY")\n"
    MESSAGE+="• 💨 Wind: $WIND_KPH km/h ($WIND_DIR) → $(get_advice wind "$WIND_KPH") $(get_emoji wind "$WIND_KPH")\n"
    MESSAGE+="• 🌧 Rain: $PRECIP mm → $(get_advice rain "$PRECIP") $(get_emoji rain "$PRECIP")\n"
    MESSAGE+="• 🌞 UV: $UV → $(get_advice uv "$UV") $(get_emoji uv "$UV")\n"
    MESSAGE+="• 📊 Pressure: $PRESSURE_IN inHg → $(get_advice pressure "$PRESSURE_IN") $(get_emoji pressure "$PRESSURE_IN")\n"
    MESSAGE+="• 🌫 Air Quality: AQI $AQI (PM2.5: $PM25 µg/m³) → $(get_advice pollution "$AQI") $(get_emoji pollution "$AQI")\n"
    MESSAGE+="• 👁 Visibility: $VIS km → $(get_advice visibility "$VIS") $(get_emoji visibility "$VIS")\n\n"

    MESSAGE+="📅 Upcoming Hours Forecast:\n"
    LOCAL_HOUR=$(echo "$FORECAST" | jq -r '.location.localtime' | cut -d' ' -f2 | cut -d: -f1)
    for i in {1..3}; do
        idx=$((10#$LOCAL_HOUR + i))
        day=0
        if (( idx > 23 )); then
            idx=$((idx - 24))
            day=1
        fi
        hr_time_24hr=$(echo "$FORECAST" | jq -r ".forecast.forecastday[$day].hour[$idx].time" | cut -d' ' -f2)
        hr_time=$(format_time_12hr "$hr_time_24hr")
        hr_temp=$(echo "$FORECAST" | jq -r ".forecast.forecastday[$day].hour[$idx].temp_c")
        hr_rain=$(echo "$FORECAST" | jq -r ".forecast.forecastday[$day].hour[$idx].precip_mm")
        hr_pressure=$(echo "$FORECAST" | jq -r ".forecast.forecastday[$day].hour[$idx].pressure_in")
        hr_advice=$(get_advice rain "$hr_rain")
        hr_emoji=$(get_emoji rain "$hr_rain")

        MESSAGE+="• $hr_time → $hr_temp°C, $hr_rain mm, $hr_pressure inHg"
        [[ -n "$hr_advice" ]] && MESSAGE+=" → $hr_advice $hr_emoji"
        MESSAGE+="\n"
    done

    MESSAGE+="\n📄 Daily Peaks:\n"
    for i in 0 1; do
        day_date=$(echo "$FORECAST" | jq -r ".forecast.forecastday[$i].date")
        
        # Use the improved extraction function
        local peak_data=$(extract_peak_data "$FORECAST" "$i")
        IFS='|' read -r max_temp max_temp_time min_temp min_temp_time peak_uv uv_hour rain_peak rain_time temp_advice temp_emoji rain_advice rain_emoji uv_advice uv_emoji <<< "$peak_data"

        MESSAGE+="• $day_date:\n"
        MESSAGE+="  - 🌡 Max Temp: ${max_temp}°C at $max_temp_time → $temp_advice $temp_emoji\n"
        MESSAGE+="  - 🌡 Min Temp: ${min_temp}°C at $min_temp_time → $temp_advice $temp_emoji\n"
        MESSAGE+="  - 🌞 Peak UV: ${peak_uv} at $uv_hour → $uv_advice $uv_emoji\n"
        MESSAGE+="  - 🌧 Peak Rain: ${rain_peak} mm at $rain_time → $rain_advice $rain_emoji\n\n"
    done

    MESSAGE+="🌌 Astronomy:\n"
    MESSAGE+="🌅 Sunrise: $SUNRISE | 🌇 Sunset: $SUNSET\n"
    MESSAGE+="🌙 Moonrise: $MOONRISE | 🌘 Moonset: $MOONSET\n"
    MESSAGE+="🌔 Moon Phase: $MOON_PHASE\n"
    
    # Get current time in 12-hour format with explicit AM/PM
    current_hour=$(date +%-H)
    current_minute=$(date +%M)
    if [[ $current_hour -ge 12 ]]; then
        period="PM"
        [[ $current_hour -gt 12 ]] && current_hour=$((current_hour - 12))
    else
        period="AM"
        [[ $current_hour -eq 0 ]] && current_hour=12
    fi
    current_time_12hr="${current_hour}:${current_minute} ${period}"
    
    kdialog --title "Weather Update - $CITY ($current_time_12hr)" --msgbox "$MESSAGE" &
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
            # Get current time for log message
            current_hour=$(date +%-H)
            current_minute=$(date +%M)
            if [[ $current_hour -ge 12 ]]; then
                period="PM"
                [[ $current_hour -gt 12 ]] && current_hour=$((current_hour - 12))
            else
                period="AM"
                [[ $current_hour -eq 0 ]] && current_hour=12
            fi
            current_time_12hr="${current_hour}:${current_minute} ${period}"
            echo "$(date): Weather update sent successfully at $current_time_12hr"
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
