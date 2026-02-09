#!/usr/bin/env bash
# Weather Alarm Script (enhanced multi‑day peaks) - COMPLETE FIXED VERSION
# Dependencies: curl, jq, bc, notify-send, kdialog
# Setup: export WEATHER_API_KEY="your_key" in ~/.bashrc

LOCK_FILE="/tmp/weather_alarm_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

# Store our PID
echo $$ > "$LOCK_FILE"

# Enhanced cleanup that only removes our PID file
cleanup() {
    # Only remove if it's our PID (prevents removing another process's lock)
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9
    exec 9>&-
}

trap cleanup EXIT

# ------------------------
# Enhanced Logging System
# ------------------------
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3

# Set default log level (can be overridden with WEATHER_LOG_LEVEL env var)
LOG_LEVEL=${WEATHER_LOG_LEVEL:-$LOG_LEVEL_INFO}
LOG_FILE="${WEATHER_LOG_FILE:-$HOME/scriptlogs/weather_log.txt}"
ALERT_STATE_FILE="$HOME/.weather_alert_state.json"

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

setup_log_rotation() {
    local max_size=500000  # 500KB
    
    if [[ -f "$LOG_FILE" ]] && (( $(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) > max_size )); then
        log_info "Rotating log file (size exceeded ${max_size} bytes)"
        mv "$LOG_FILE" "${LOG_FILE}.old" 2>/dev/null || true
        touch "$LOG_FILE"
        
        # Clean up old logs (keep only 5 most recent)
        ls -tp "$LOG_FILE".* 2>/dev/null | tail -n +6 | xargs -r rm -- 2>/dev/null || true
    fi
}

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local level_str=""
    
    case "$level" in
        $LOG_LEVEL_DEBUG) level_str="DEBUG" ;;
        $LOG_LEVEL_INFO) level_str="INFO" ;;
        $LOG_LEVEL_WARN) level_str="WARN" ;;
        $LOG_LEVEL_ERROR) level_str="ERROR" ;;
        *) level_str="UNKNOWN" ;;
    esac
    
    local log_entry="[$timestamp] [$level_str] $message"
    
    # Only print to terminal for WARN and ERROR, or if debug mode
    if [[ $level -ge $LOG_LEVEL_WARN ]] || [[ $LOG_LEVEL -eq $LOG_LEVEL_DEBUG ]]; then
        echo "$log_entry"
    fi
    
    # Always append to log file
    echo "$log_entry" >> "$LOG_FILE"
}

log_debug() { log $LOG_LEVEL_DEBUG "$1"; }
log_info() { log $LOG_LEVEL_INFO "$1"; }
log_warn() { log $LOG_LEVEL_WARN "$1"; }
log_error() { log $LOG_LEVEL_ERROR "$1"; }

# Function tracing for debugging
log_function_enter() {
    log_debug "ENTER: ${FUNCNAME[1]} - Args: $*"
}

log_function_exit() {
    log_debug "EXIT: ${FUNCNAME[1]} - Return: $1"
}

# Variable state logging
log_variable() {
    local var_name="$1"
    local var_value="$2"
    log_debug "VAR: $var_name = '$var_value'"
}

# API call logging
log_api_call() {
    log_debug "API CALL: $1"
}

log_api_response() {
    log_debug "API RESPONSE: ${1:0:200}..."  # First 200 chars to avoid huge logs
}

# ------------------------
# Alert State Management
# ------------------------
save_alert_state() {
    local alert_type="$1"
    local value="$2"
    local timestamp=$(date +%s)
    
    # Create or update state file
    if [[ -f "$ALERT_STATE_FILE" ]]; then
        local current_state=$(cat "$ALERT_STATE_FILE")
    else
        local current_state="{}"
    fi
    
    local new_state=$(echo "$current_state" | jq --arg type "$alert_type" \
        --argjson value "$value" \
        --argjson time "$timestamp" \
        '. + {($type): {"value": $value, "time": $time}}' 2>/dev/null)
    
    if [[ -n "$new_state" ]]; then
        echo "$new_state" > "$ALERT_STATE_FILE"
    fi
}

should_alert() {
    local alert_type="$1"
    local current_value="$2"
    local threshold="${3:-0}"
    
    # Ensure numeric values for calculations
    current_value=${current_value:-0}
    threshold=${threshold:-0}
    
    if [[ ! -f "$ALERT_STATE_FILE" ]]; then
        return 0  # Always alert if no state file
    fi
    
    local state=$(cat "$ALERT_STATE_FILE" 2>/dev/null || echo "{}")
    local last_value=$(echo "$state" | jq -r ".\"$alert_type\".value // \"\"" 2>/dev/null)
    local last_time=$(echo "$state" | jq -r ".\"$alert_type\".time // \"\"" 2>/dev/null)
    
    # If no previous state, alert
    if [[ -z "$last_value" ]]; then
        return 0
    fi
    
    # Ensure last_value is numeric
    last_value=${last_value:-0}
    
    # Check if value changed significantly or last alert was more than 1 hour ago
    local value_diff=$(echo "scale=2; $current_value - $last_value" | bc -l 2>/dev/null || echo "999")
    local time_diff=$(( $(date +%s) - last_time ))
    
    if (( $(echo "($value_diff >= $threshold) || ($value_diff <= -$threshold)" | bc -l 2>/dev/null || echo 1) )) || \
       (( time_diff > 3600 )); then
        return 0
    fi
    
    return 1
}

# ------------------------
# Configuration & API Key Management
# ------------------------
initialize_script() {
    log_function_enter
    
    if [[ -n "$WEATHER_API_KEY" ]]; then
        API_KEY="$WEATHER_API_KEY"
        log_debug "Using API key from environment variable"
    elif command -v secret-tool >/dev/null 2>&1; then
        API_KEY=$(secret-tool lookup service weatherapi username "$(whoami)" 2>/dev/null)
        log_debug "Using API key from secret-tool"
    else
        log_error "Weather API key not found"
        echo "Weather API key not found. Please set it using:"
        echo "export WEATHER_API_KEY='your_key_here' in ~/.bashrc"
        return 1
    fi

    # Validate API key (simple check)
    if [[ ${#API_KEY} -lt 20 ]]; then
        log_warn "API key seems too short; double check it."
    fi

    BASE_URL="http://api.weatherapi.com/v1"
    INTERVAL=1800
    ALERT_WINDOW=30

    # Setup log rotation
    setup_log_rotation
    
    log_debug "Configuration loaded: BASE_URL=$BASE_URL, INTERVAL=$INTERVAL, ALERT_WINDOW=$ALERT_WINDOW"
    log_function_exit "success"
    return 0
}

# ------------------------
# Utilities
# ------------------------
compare_bc() {
    local expression="$1"
    # Ensure expression is valid before passing to bc
    if [[ -z "$expression" ]]; then
        return 1
    fi
    local result=$(echo "$expression" | bc -l 2>/dev/null || echo "0")
    [[ "$result" == "1" ]]
}

safe_extract_value() {
    local json="$1"
    local path="$2"
    local default="$3"
    
    local value=$(echo "$json" | jq -r "$path" 2>/dev/null)
    if [[ "$value" == "null" || -z "$value" || "$value" == "null" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

deg_to_dir() {
    log_function_enter "$1"
    local deg="$1"
    log_variable "deg" "$deg"
    
    # GUARD: Validate input is a number
    if ! [[ "$deg" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        log_error "Invalid degree input: $deg"
        log_function_exit "Unknown"
        echo "Unknown"
        return 1
    fi
    
    # GUARD: Protect bc from invalid operations
    local normalized_deg=$(echo "scale=0; ($deg + 360) % 360" | bc -l 2>/dev/null)
    if [[ $? -ne 0 || -z "$normalized_deg" ]]; then
        log_error "BC calculation failed for degree: $deg"
        log_function_exit "Unknown"
        echo "Unknown"
        return 1
    fi
    
    local directions=("N" "NNE" "NE" "ENE" "E" "ESE" "SE" "SSE" 
                      "S" "SSW" "SW" "WSW" "W" "WNW" "NW" "NNW")
    local idx=$(echo "scale=0; ($normalized_deg + 11.25) / 22.5" | bc -l)
    idx=${idx%.*}  # Remove decimal part
    
    # Handle index out of bounds
    if [[ $idx -ge 16 ]]; then
        idx=0
    fi
    
    local result="${directions[$idx]}"
    log_debug "Converted $deg° to $result (normalized: $normalized_deg, index: $idx)"
    log_function_exit "$result"
    echo "$result"
}

time_to_minutes() {
    log_function_enter "$1"
    local time_str="$1"
    local hour minute
    log_variable "time_str" "$time_str"

    [[ -z "$time_str" ]] && { 
        log_error "Empty time string"
        log_function_exit "0"
        echo "0"; 
        return 1; 
    }

    if [[ ! "$time_str" =~ (AM|PM|am|pm) ]]; then
        hour=$(echo "$time_str" | cut -d: -f1 | sed 's/^0*//')
        minute=$(echo "$time_str" | cut -d: -f2 | sed 's/^0*//')
        [[ ! "$hour" =~ ^[0-9]+$ ]] && { 
            log_error "Invalid hour in 24h time: $hour"
            log_function_exit "0"
            echo "0"; 
            return 1; 
        }
        [[ ! "$minute" =~ ^[0-9]+$ ]] && { 
            log_error "Invalid minute in 24h time: $minute"
            log_function_exit "0"
            echo "0"; 
            return 1; 
        }
        # FIXED: Use base-10 conversion for comparisons
        [[ $((10#$hour)) -gt 23 ]] && { 
            log_error "Hour out of range: $hour"
            log_function_exit "0"
            echo "0"; 
            return 1; 
        }
        [[ $((10#$minute)) -gt 59 ]] && { 
            log_error "Minute out of range: $minute"
            log_function_exit "0"
            echo "0"; 
            return 1; 
        }
        # FIXED: Use base-10 conversion to prevent octal interpretation
        local result=$(( (10#$hour) * 60 + (10#$minute) ))
        log_debug "24h time $time_str converted to $result minutes"
        log_function_exit "$result"
        echo $result
        return 0
    fi

    hour=$(echo "$time_str" | cut -d: -f1 | sed 's/^0*//')
    minute=$(echo "$time_str" | cut -d: -f2 | sed 's/[^0-9]//g')
    [[ ! "$hour" =~ ^[0-9]+$ ]] && { 
        log_error "Invalid hour in 12h time: $hour"
        log_function_exit "0"
        echo "0"; 
        return 1; 
    }
    [[ ! "$minute" =~ ^[0-9]+$ ]] && { 
        log_error "Invalid minute in 12h time: $minute"
        log_function_exit "0"
        echo "0"; 
        return 1; 
    }
    # FIXED: Use base-10 conversion for comparisons
    [[ $((10#$hour)) -gt 12 || $((10#$hour)) -lt 1 ]] && { 
        log_error "Hour out of 12h range: $hour"
        log_function_exit "0"
        echo "0"; 
        return 1; 
    }
    [[ $((10#$minute)) -gt 59 ]] && { 
        log_error "Minute out of range: $minute"
        log_function_exit "0"
        echo "0"; 
        return 1; 
    }

    if [[ "$time_str" =~ (AM|am) ]]; then
        [[ $hour -eq 12 ]] && hour=0
    elif [[ "$time_str" =~ (PM|pm) ]]; then
        [[ $hour -ne 12 ]] && hour=$((hour + 12))
    fi

    # FIXED: Use base-10 conversion to prevent octal interpretation
    local result=$(( (10#$hour) * 60 + (10#$minute) ))
    log_debug "12h time $time_str converted to $result minutes (24h: $hour:$minute)"
    log_function_exit "$result"
    echo $result
}

# Convert 24-hour time to 12-hour format with AM/PM
format_time_12hr() {
    log_function_enter "$1"
    local time_24hr="$1"
    local hour minute ampm
    
    # Extract hour and minute, remove leading zeros for bash arithmetic
    hour=$(echo "$time_24hr" | cut -d: -f1 | sed 's/^0*//')
    minute=$(echo "$time_24hr" | cut -d: -f2 | sed 's/^0*//')
    
    # Handle empty values
    hour=${hour:-0}
    minute=${minute:-0}
    
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
    
    # Safe printf without octal interpretation
    minute=$(printf "%02d" "$((10#$minute))")
    
    local result="${hour}:${minute} ${ampm}"
    log_debug "Converted $time_24hr to $result"
    log_function_exit "$result"
    echo "$result"
}

# API response validation
check_api_response() {
    local response="$1"
    local endpoint="$2"
    log_function_enter "$endpoint"
    log_variable "endpoint" "$endpoint"
    log_api_response "$response"

    # Guard against empty responses
    if [[ -z "$response" || "$response" == "null" ]]; then
        log_error "Empty or null response from $endpoint API"
        log_function_exit "1"
        return 1
    fi

    # Guard against non-JSON responses (like HTML error pages)
    if [[ ! "$response" =~ ^[[:space:]]*\{ ]] && [[ ! "$response" =~ ^[[:space:]]*\[ ]]; then
        log_error "Non-JSON response from $endpoint API: ${response:0:100}..."
        log_function_exit "1"
        return 1
    fi

    # Guard against jq parsing failures
    if ! echo "$response" | jq -e . >/dev/null 2>&1; then
        log_error "Invalid JSON structure from $endpoint API"
        log_function_exit "1"
        return 1
    fi

    # Guard against API error messages
    local error=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
    if [[ -n "$error" ]]; then
        log_error "API Error ($endpoint): $error"
        log_function_exit "1"
        return 1
    fi

    log_debug "API response validation successful for $endpoint"
    log_function_exit "0"
    return 0
}

# ------------------------
# Advice System (with pressure in inHg)
# ------------------------
give_advice() {
    log_function_enter "$1"
    local advice_type="$1"
    local advice=""
    
    case "$advice_type" in
        "heat_extreme") advice="Stay indoors, hydrate" ;;
        "heat_high") advice="Avoid sun, drink water" ;;
        "heat_mild") advice="Stay hydrated" ;;
        "heat_low") advice="Pleasant weather" ;;
        "cold_extreme") advice="Layer up, limit outdoors" ;;
        "cold_high") advice="Heavy coat needed" ;;
        "cold_mild") advice="Light jacket recommended" ;;
        "cold_low") advice="Dress comfortably" ;;
        "humidity_extreme") advice="Use AC/dehumidifier" ;;
        "humidity_high") advice="Stay cool" ;;
        "humidity_moderate") advice="Slightly heavy air" ;;
        "humidity_low") advice="Dry air" ;;
        "rain_storm") advice="Seek shelter" ;;
        "rain_heavy") advice="Stay indoors" ;;
        "rain_moderate") advice="Use umbrella, raincoat and boots" ;;
		"rain_light") advice="Use umbralla" ;;
        "rain_none") advice="No rain" ;;
        "wind_storm") advice="Stay indoors" ;;
        "wind_strong") advice="Secure items" ;;
        "wind_moderate") advice="Steady breeze" ;;
        "wind_light") advice="Gentle breeze" ;;
        "wind_none") advice="Calm" ;;
        "uv_extreme") advice="Stay in shade" ;;
        "uv_high") advice="Sunscreen + hat/umbrella" ;;
        "uv_moderate") advice="Use sunscreen" ;;
        "uv_low") advice="Safe sun exposure" ;;
        "pollution_extreme") advice="Stay indoors" ;;
        "pollution_very_unhealthy") advice="Avoid outdoors" ;;
        "pollution_high") advice="Limit exposure" ;;
        "pollution_moderate") advice="Use caution" ;;
        "pollution_light") advice="Mostly fine air" ;;
        "pressure_very_high") advice="Very high - clear" ;;
        "pressure_high") advice="High - fair" ;;
        "pressure_normal") advice="Normal - typical" ;;
        "pressure_low") advice="Low - rain likely" ;;
        "pressure_very_low") advice="Very low - storms" ;;
        "thunderstorm") advice="Stay inside" ;;
        "fog") advice="Drive carefully" ;;
        "snow") advice="Dress warm" ;;
        "sunrise") advice="Start your day fresh" ;;
        "sunset") advice="Relax and enjoy the evening" ;;
        "moonrise") advice="Look up at the rising Moon" ;;
        "moonset") advice="Catch the Moon before it sets" ;;
        "full_moon") advice="Perfect night for stargazing" ;;
        "new_moon") advice="Ideal time to spot faint stars" ;;
        "first_quarter") advice="Half-lit Moon in the sky" ;;
        "last_quarter") advice="Waning Moon for night observation" ;;
        "eclipse") advice="Don't miss this celestial event" ;;
        *) advice="" ;;
    esac
    
    log_debug "Advice for $advice_type: $advice"
    log_function_exit "$advice"
    echo "$advice"
}

# Fixed assessment function - compute once, reuse results
assess_weather() {
    log_function_enter "$1 $2 $3"
    local type="$1" value="$2" unit="$3"
    local level advice emoji alert_threshold=0
    log_variable "type" "$type"
    log_variable "value" "$value"
    log_variable "unit" "$unit"

    # Ensure value is numeric for comparisons
    if ! [[ "$value" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        value=0
    fi

    case "$type" in
        "temperature")
            if compare_bc "$value >= 40"; then
                level="extreme_heat"; advice=$(give_advice heat_extreme); emoji="🔥"; alert_threshold=1
            elif compare_bc "$value >= 35"; then
                level="high_heat"; advice=$(give_advice heat_high); emoji="🔥"
            elif compare_bc "$value >= 30"; then
                level="moderate_heat"; advice=$(give_advice heat_mild); emoji="🌡"
            elif compare_bc "$value >= 25"; then
                level="mild_heat"; advice=$(give_advice heat_low); emoji="🌤"
            elif compare_bc "$value >= 20"; then
                level="pleasant"; advice=$(give_advice heat_low); emoji="😊"
            elif compare_bc "$value >= 15"; then
                level="cool"; advice=$(give_advice cold_low); emoji="🧥"
            elif compare_bc "$value >= 5"; then
                level="cold"; advice=$(give_advice cold_mild); emoji="❄️"
            elif compare_bc "$value >= 0"; then
                level="very_cold"; advice=$(give_advice cold_high); emoji="🥶"
            else
                level="extreme_cold"; advice=$(give_advice cold_extreme); emoji="🥶"; alert_threshold=1
            fi
            ;;
        "rain")
            if compare_bc "$value >= 50"; then
                level="storm"; advice=$(give_advice rain_storm); emoji="⛈"; alert_threshold=1
            elif compare_bc "$value >= 7.6"; then
                level="heavy"; advice=$(give_advice rain_heavy); emoji="🌧"; alert_threshold=1
            elif compare_bc "$value >= 2.5"; then
                level="moderate"; advice=$(give_advice rain_moderate); emoji="🌧"; alert_threshold=1
            elif compare_bc "$value > 0"; then
                level="light"; advice=$(give_advice rain_light); emoji="🌦"; alert_threshold=1
            else
                level="none"; advice=$(give_advice rain_none); emoji="☀️"
            fi
            ;;
        "wind")
            if compare_bc "$value >= 80"; then
                level="storm"; advice=$(give_advice wind_storm); emoji="🌪"; alert_threshold=1
            elif compare_bc "$value >= 40"; then
                level="strong"; advice=$(give_advice wind_strong); emoji="💨"; alert_threshold=1
            elif compare_bc "$value >= 20"; then
                level="moderate"; advice=$(give_advice wind_moderate); emoji="💨"
            elif compare_bc "$value >= 10"; then
                level="light"; advice=$(give_advice wind_light); emoji="🍃"
            else
                level="calm"; advice=$(give_advice wind_none); emoji="🌀"
            fi
            ;;
        "uv")
            if compare_bc "$value >= 8"; then
                level="extreme"; advice=$(give_advice uv_extreme); emoji="🔥"; alert_threshold=1
            elif compare_bc "$value >= 6"; then
                level="high"; advice=$(give_advice uv_high); emoji="😎"; alert_threshold=1
            elif compare_bc "$value >= 3"; then
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
            if compare_bc "$value >= 85"; then
                level="extreme"; advice=$(give_advice humidity_extreme); emoji="💦"
            elif compare_bc "$value >= 70"; then
                level="high"; advice=$(give_advice humidity_high); emoji="💧"
            elif compare_bc "$value >= 50"; then
                level="moderate"; advice=$(give_advice humidity_moderate); emoji="💧"
            else
                level="low"; advice=$(give_advice humidity_low); emoji="🏜"
            fi
            ;;
        "visibility")
            if compare_bc "$value >= 10"; then
                level="excellent"; advice="Excellent visibility"; emoji="👁"
            elif compare_bc "$value >= 5"; then
                level="good"; advice="Good visibility"; emoji="👁"
            elif compare_bc "$value >= 2"; then
                level="moderate"; advice="Moderate visibility"; emoji="🌫"
            elif compare_bc "$value >= 1"; then
                level="poor"; advice="Poor visibility"; emoji="🌫"
            else
                level="very_poor"; advice="Very poor visibility"; emoji="🌫"
            fi
            ;;
        "pressure")
            # Atmospheric pressure in inches of mercury (inHg) - FIXED thresholds
            if compare_bc "$value >= 30.2"; then
                level="very_high"; advice=$(give_advice pressure_very_high); emoji="🔵"
            elif compare_bc "$value >= 29.9"; then
                level="high"; advice=$(give_advice pressure_high); emoji="🔷"
            elif compare_bc "$value >= 29.5"; then
                level="normal"; advice=$(give_advice pressure_normal); emoji="🌤"
            elif compare_bc "$value >= 29.0"; then
                level="low"; advice=$(give_advice pressure_low); emoji="🌧"; alert_threshold=1
            else
                level="very_low"; advice=$(give_advice pressure_very_low); emoji="⛈"; alert_threshold=1
            fi
            ;;
    esac

    local result="$level|$advice|$emoji|$alert_threshold|$value|$unit"
    log_debug "Assessment for $type: level=$level, alert=$alert_threshold, advice=$advice"
    log_function_exit "$result"
    echo "$result"
}

# Helper function to get all metrics at once (FIXED recursion issue)
get_weather_metrics() {
    local type="$1" value="$2" unit="$3"
    local assessment=$(assess_weather "$type" "$value" "$unit")
    echo "$assessment"
}

validate_coordinates() {
    log_function_enter "$1"
    local coords="$1"
    log_variable "coords" "$coords"
    
    # Check if coordinates match the pattern: lat,lon (with optional negative signs)
    if [[ ! "$coords" =~ ^-?[0-9]{1,3}\.[0-9]+,-?[0-9]{1,3}\.[0-9]+$ ]]; then
        log_error "Coordinate format invalid: $coords"
        log_function_exit "1"
        return 1
    fi
    
    # Extract latitude and longitude
    local lat=$(echo "$coords" | cut -d, -f1)
    local lon=$(echo "$coords" | cut -d, -f2)
    
    # Validate latitude range (-90 to 90)
    if compare_bc "$lat < -90" || compare_bc "$lat > 90"; then
        log_error "Latitude out of range: $lat"
        log_function_exit "1"
        return 1
    fi
    
    # Validate longitude range (-180 to 180)
    if compare_bc "$lon < -180" || compare_bc "$lon > 180"; then
        log_error "Longitude out of range: $lon"
        log_function_exit "1"
        return 1
    fi
    
    log_debug "Coordinates validated successfully: lat=$lat, lon=$lon"
    log_function_exit "0"
    return 0
}

# ------------------------
# Location detection
# ------------------------
CURL_OPTS=(
  -sS
  --connect-timeout 20
  --max-time 30
  --retry 5
  --retry-delay 5
  --retry-max-time 60
  --retry-all-errors
  -L
  --compressed
)

get_location() {
    log_info "Detecting precise location..."

    # --- Attempt 1: ip-api.com ---
    local geo_data=$(curl -s "http://ip-api.com/json/")
    LAT=$(echo "$geo_data" | jq -r '.lat // empty')
    LON=$(echo "$geo_data" | jq -r '.lon // empty')

    # --- Attempt 2: ipapi.co (Fallback) ---
    if [[ -z "$LAT" || -z "$LON" ]]; then
        log_warn "Primary geo-detection failed. Trying ipapi.co..."
        geo_data=$(curl -s "https://ipapi.co/json/")
        LAT=$(echo "$geo_data" | jq -r '.latitude // empty')
        LON=$(echo "$geo_data" | jq -r '.longitude // empty')
    fi

    # --- Validation & Reverse Geocoding ---
    if [[ -n "$LAT" && -n "$LON" ]]; then
        # Map the coordinates to a real city/district name (e.g., Talisay vs Cebu City)
        # We use a custom User-Agent to comply with Nominatim's usage policy
        CITY=$(curl -s -A "WeatherAlarmScript/1.0" \
            "https://nominatim.openstreetmap.org/reverse?lat=$LAT&lon=$LON&format=json" \
            | jq -r '.address.city // .address.town // .address.municipality // .address.village // "Unknown Location"')
        
        WEATHER_QUERY="$LAT,$LON"
        log_info "Location Found: $CITY ($WEATHER_QUERY)"
    else
        log_error "Critical: Could not detect location from any service."
        return 1
    fi
}

# ------------------------
# Fetch weather data (forecast + astronomy)
# ------------------------
get_weather() {
    log_function_enter
    log_variable "LAT" "$LAT"
    log_variable "LON" "$LON"
    
    log_api_call "WeatherAPI forecast"
    FORECAST=$(curl "${CURL_OPTS[@]}" \
        "$BASE_URL/forecast.json?key=$API_KEY&q=$LAT,$LON&days=2&aqi=yes&alerts=yes")
    if ! check_api_response "$FORECAST" "forecast"; then
        log_error "Failed to fetch weather data"
        log_function_exit "failure"
        return 1
    fi

    log_api_call "WeatherAPI astronomy"
    ASTRONOMY=$(curl "${CURL_OPTS[@]}" \
        "$BASE_URL/astronomy.json?key=$API_KEY&q=$LAT,$LON")
    if ! check_api_response "$ASTRONOMY" "astronomy"; then
        log_warn "Failed to fetch astronomy data. Continuing with weather only..."
        ASTRONOMY='{"astronomy":{"astro":{"sunrise":"","sunset":"","moonrise":"","moonset":"","moon_phase":""}}}'
    fi

    # Use safe extraction for all values
    TEMP_C=$(safe_extract_value "$FORECAST" '.current.temp_c' '0')
    FEELS=$(safe_extract_value "$FORECAST" '.current.feelslike_c' '0')
    HUMIDITY=$(safe_extract_value "$FORECAST" '.current.humidity' '0')
    WIND_KPH=$(safe_extract_value "$FORECAST" '.current.wind_kph' '0')
    WIND_DIR_DEG=$(safe_extract_value "$FORECAST" '.current.wind_degree' '0')
    WIND_DIR=$(deg_to_dir "$WIND_DIR_DEG")
    PRECIP=$(safe_extract_value "$FORECAST" '.current.precip_mm' '0')
    UV=$(safe_extract_value "$FORECAST" '.current.uv' '0')
    VIS=$(safe_extract_value "$FORECAST" '.current.vis_km' '0')
    PRESSURE_MB=$(safe_extract_value "$FORECAST" '.current.pressure_mb' '0')
    PRESSURE_IN=$(safe_extract_value "$FORECAST" '.current.pressure_in' '0')
    CONDITION=$(safe_extract_value "$FORECAST" '.current.condition.text' '')
    AQI=$(safe_extract_value "$FORECAST" '.current.air_quality["us-epa-index"]' '0')
    PM25=$(safe_extract_value "$FORECAST" '.current.air_quality.pm2_5' '0')

    SUNRISE=$(safe_extract_value "$ASTRONOMY" '.astronomy.astro.sunrise' '')
    SUNSET=$(safe_extract_value "$ASTRONOMY" '.astronomy.astro.sunset' '')
    MOONRISE=$(safe_extract_value "$ASTRONOMY" '.astronomy.astro.moonrise' '')
    MOONSET=$(safe_extract_value "$ASTRONOMY" '.astronomy.astro.moonset' '')
    MOON_PHASE=$(safe_extract_value "$ASTRONOMY" '.astronomy.astro.moon_phase' '')

    # Log all extracted values
    log_debug "Weather data extracted: TEMP_C=$TEMP_C, HUMIDITY=$HUMIDITY, WIND_KPH=$WIND_KPH, PRECIP=$PRECIP, UV=$UV, PRESSURE_IN=$PRESSURE_IN, AQI=$AQI"
    log_debug "Astronomy data: SUNRISE=$SUNRISE, SUNSET=$SUNSET, MOON_PHASE=$MOON_PHASE"
    
    log_function_exit "success"
    return 0
}

# ------------------------
# Data extraction functions
# ------------------------
extract_peak_data() {
    log_function_enter "$2"
    local forecast_json="$1"
    local day_index="$2"
    log_variable "day_index" "$day_index"
    
    # GUARD: Validate input JSON
    if [[ -z "$forecast_json" || "$forecast_json" == "null" ]]; then
        log_error "Empty or null forecast JSON for day $day_index"
        log_function_exit "fallback"
        echo "0|Unknown|0|Unknown|0|Unknown|0|Unknown||||||"
        return 1
    fi

    # GUARD: Validate day index exists
    local day_count=$(echo "$forecast_json" | jq -r '.forecast.forecastday | length' 2>/dev/null)
    if [[ "$day_count" -le "$day_index" ]]; then
        log_error "Day index $day_index out of range (total days: $day_count)"
        log_function_exit "fallback"
        echo "0|Unknown|0|Unknown|0|Unknown|0|Unknown||||||"
        return 1
    fi

    # Extract all peak data
    local max_temp_data=$(echo "$forecast_json" | jq -r ".forecast.forecastday[$day_index].hour | [.[] | select(.temp_c != null)] | max_by(.temp_c) | {time: .time, value: .temp_c} // \"\"" 2>/dev/null)
    local min_temp_data=$(echo "$forecast_json" | jq -r ".forecast.forecastday[$day_index].hour | [.[] | select(.temp_c != null)] | min_by(.temp_c) | {time: .time, value: .temp_c} // \"\"" 2>/dev/null)
    local uv_data=$(echo "$forecast_json" | jq -r ".forecast.forecastday[$day_index].hour | [.[] | select(.uv != null and .uv >= 0)] | max_by(.uv) | {time: .time, value: .uv} // \"\"" 2>/dev/null)
    local rain_data=$(echo "$forecast_json" | jq -r ".forecast.forecastday[$day_index].hour | [.[] | select(.precip_mm != null)] | max_by(.precip_mm) | {time: .time, value: .precip_mm} // \"\"" 2>/dev/null)

    # Parse extracted data with fallbacks
    local max_temp_value="0" max_temp_time="Unknown"
    local min_temp_value="0" min_temp_time="Unknown" 
    local peak_uv_value="0" uv_hour="Unknown"
    local rain_peak="0" rain_time="Unknown"

    [[ -n "$max_temp_data" && "$max_temp_data" != "null" ]] && {
        max_temp_value=$(echo "$max_temp_data" | jq -r '.value // 0')
        local temp_time=$(echo "$max_temp_data" | jq -r '.time // ""')
        [[ -n "$temp_time" ]] && max_temp_time=$(echo "$temp_time" | cut -d' ' -f2)
    }

    [[ -n "$min_temp_data" && "$min_temp_data" != "null" ]] && {
        min_temp_value=$(echo "$min_temp_data" | jq -r '.value // 0')
        local temp_time=$(echo "$min_temp_data" | jq -r '.time // ""')
        [[ -n "$temp_time" ]] && min_temp_time=$(echo "$temp_time" | cut -d' ' -f2)
    }

    [[ -n "$uv_data" && "$uv_data" != "null" ]] && {
        peak_uv_value=$(echo "$uv_data" | jq -r '.value // 0')
        local uv_time=$(echo "$uv_data" | jq -r '.time // ""')
        [[ -n "$uv_time" ]] && uv_hour=$(echo "$uv_time" | cut -d' ' -f2)
    }

    [[ -n "$rain_data" && "$rain_data" != "null" ]] && {
        rain_peak=$(echo "$rain_data" | jq -r '.value // 0')
        local rain_time_raw=$(echo "$rain_data" | jq -r '.time // ""')
        [[ -n "$rain_time_raw" ]] && rain_time=$(echo "$rain_time_raw" | cut -d' ' -f2)
    }

    # Format times
    [[ "$max_temp_time" != "Unknown" ]] && max_temp_time=$(format_time_12hr "$max_temp_time" 2>/dev/null || echo "Unknown")
    [[ "$min_temp_time" != "Unknown" ]] && min_temp_time=$(format_time_12hr "$min_temp_time" 2>/dev/null || echo "Unknown")
    [[ "$uv_hour" != "Unknown" ]] && uv_hour=$(format_time_12hr "$uv_hour" 2>/dev/null || echo "Unknown")
    [[ "$rain_time" != "Unknown" ]] && rain_time=$(format_time_12hr "$rain_time" 2>/dev/null || echo "Unknown")

    # Get assessments once (FIXED recursion issue)
    local temp_assessment=$(get_weather_metrics temperature "$max_temp_value" "°C")
    local rain_assessment=$(get_weather_metrics rain "$rain_peak" "mm") 
    local uv_assessment=$(get_weather_metrics uv "$peak_uv_value" "")

    local temp_advice=$(echo "$temp_assessment" | cut -d'|' -f2)
    local temp_emoji=$(echo "$temp_assessment" | cut -d'|' -f3)
    local rain_advice=$(echo "$rain_assessment" | cut -d'|' -f2)
    local rain_emoji=$(echo "$rain_assessment" | cut -d'|' -f3)
    local uv_advice=$(echo "$uv_assessment" | cut -d'|' -f2)
    local uv_emoji=$(echo "$uv_assessment" | cut -d'|' -f3)

    local result="${max_temp_value:-0}|${max_temp_time:-Unknown}|${min_temp_value:-0}|${min_temp_time:-Unknown}|${peak_uv_value:-0}|${uv_hour:-Unknown}|${rain_peak:-0}|${rain_time:-Unknown}|${temp_advice}|${temp_emoji}|${rain_advice}|${rain_emoji}|${uv_advice}|${uv_emoji}"
    
    log_debug "Peak data for day $day_index: max_temp=$max_temp_value, min_temp=$min_temp_value, uv=$peak_uv_value, rain=$rain_peak"
    log_function_exit "success"
    echo "$result"
}

# ------------------------
# Alert Generation Functions
# ------------------------
generate_alerts() {
    log_function_enter
    ALERTS=()

    # Get all weather metrics at once (FIXED recursion issue)
    local temp_assessment=$(get_weather_metrics temperature "$TEMP_C" "°C")
    local rain_assessment=$(get_weather_metrics rain "$PRECIP" "mm")
    local wind_assessment=$(get_weather_metrics wind "$WIND_KPH" "km/h")
    local uv_assessment=$(get_weather_metrics uv "$UV" "")
    local pollution_assessment=$(get_weather_metrics pollution "$AQI" "")
    local pressure_assessment=$(get_weather_metrics pressure "$PRESSURE_IN" "inHg")

    # Parse assessments
    local temp_level=$(echo "$temp_assessment" | cut -d'|' -f1)
    local temp_advice=$(echo "$temp_assessment" | cut -d'|' -f2)
    local temp_emoji=$(echo "$temp_assessment" | cut -d'|' -f3)
    local temp_alert=$(echo "$temp_assessment" | cut -d'|' -f4)

    local rain_level=$(echo "$rain_assessment" | cut -d'|' -f1)
    local rain_advice=$(echo "$rain_assessment" | cut -d'|' -f2)
    local rain_emoji=$(echo "$rain_assessment" | cut -d'|' -f3)
    local rain_alert=$(echo "$rain_assessment" | cut -d'|' -f4)

    local wind_level=$(echo "$wind_assessment" | cut -d'|' -f1)
    local wind_advice=$(echo "$wind_assessment" | cut -d'|' -f2)
    local wind_emoji=$(echo "$wind_assessment" | cut -d'|' -f3)
    local wind_alert=$(echo "$wind_assessment" | cut -d'|' -f4)

    local uv_level=$(echo "$uv_assessment" | cut -d'|' -f1)
    local uv_advice=$(echo "$uv_assessment" | cut -d'|' -f2)
    local uv_emoji=$(echo "$uv_assessment" | cut -d'|' -f3)
    local uv_alert=$(echo "$uv_assessment" | cut -d'|' -f4)

    local pollution_level=$(echo "$pollution_assessment" | cut -d'|' -f1)
    local pollution_advice=$(echo "$pollution_assessment" | cut -d'|' -f2)
    local pollution_emoji=$(echo "$pollution_assessment" | cut -d'|' -f3)
    local pollution_alert=$(echo "$pollution_assessment" | cut -d'|' -f4)

    local pressure_level=$(echo "$pressure_assessment" | cut -d'|' -f1)
    local pressure_advice=$(echo "$pressure_assessment" | cut -d'|' -f2)
    local pressure_emoji=$(echo "$pressure_assessment" | cut -d'|' -f3)
    local pressure_alert=$(echo "$pressure_assessment" | cut -d'|' -f4)

    # Generate alerts with state management
    if [[ "$temp_alert" == "1" ]] && should_alert "temperature_$temp_level" "$TEMP_C" "5"; then
        case "$temp_level" in
            "extreme_heat") 
                ALERTS+=("$temp_emoji Extreme heat ($TEMP_C°C) → $temp_advice")
                save_alert_state "temperature_$temp_level" "$TEMP_C"
                ;;
            "extreme_cold") 
                ALERTS+=("$temp_emoji Extreme cold ($TEMP_C°C) → $temp_advice")
                save_alert_state "temperature_$temp_level" "$TEMP_C"
                ;;
        esac
    fi

    if [[ "$rain_alert" == "1" ]] && should_alert "rain_$rain_level" "$PRECIP" "2"; then
        case "$rain_level" in
            "storm") 
                ALERTS+=("$rain_emoji Storming ($PRECIP mm) → $rain_advice")
                save_alert_state "rain_$rain_level" "$PRECIP"
                ;;
            "heavy") 
                ALERTS+=("$rain_emoji Heavy rain ($PRECIP mm) → $rain_advice")
                save_alert_state "rain_$rain_level" "$PRECIP"
                ;;
            "moderate") 
                ALERTS+=("$rain_emoji Moderate rain ($PRECIP mm) → $rain_advice")
                save_alert_state "rain_$rain_level" "$PRECIP"
                ;;
            "light") 
                ALERTS+=("$rain_emoji Light rain ($PRECIP mm) → $rain_advice")
                save_alert_state "rain_$rain_level" "$PRECIP"
                ;;
        esac
    fi

    if [[ "$wind_alert" == "1" ]] && should_alert "wind_$wind_level" "$WIND_KPH" "10"; then
        case "$wind_level" in
            "storm") 
                ALERTS+=("$wind_emoji Storm-force wind ($WIND_KPH km/h) → $wind_advice")
                save_alert_state "wind_$wind_level" "$WIND_KPH"
                ;;
            "strong") 
                ALERTS+=("$wind_emoji Strong wind ($WIND_KPH km/h) → $wind_advice")
                save_alert_state "wind_$wind_level" "$WIND_KPH"
                ;;
        esac
    fi

    if [[ "$uv_alert" == "1" ]] && should_alert "uv_$uv_level" "$UV" "1"; then
        case "$uv_level" in
            "extreme") 
                ALERTS+=("$uv_emoji Extreme UV ($UV) → $uv_advice")
                save_alert_state "uv_$uv_level" "$UV"
                ;;
            "high") 
                ALERTS+=("$uv_emoji High UV ($UV) → $uv_advice")
                save_alert_state "uv_$uv_level" "$UV"
                ;;
        esac
    fi

    if [[ "$pollution_alert" == "1" ]] && should_alert "pollution_$pollution_level" "$AQI" "1"; then
        case "$pollution_level" in
            "unhealthy") 
                ALERTS+=("$pollution_emoji Unhealthy (AQI $AQI, PM2.5: $PM25 µg/m³) → $pollution_advice")
                save_alert_state "pollution_$pollution_level" "$AQI"
                ;;
            "very_unhealthy") 
                ALERTS+=("$pollution_emoji Very Unhealthy (AQI $AQI, PM2.5: $PM25 µg/m³) → $pollution_advice")
                save_alert_state "pollution_$pollution_level" "$AQI"
                ;;
            "hazardous") 
                ALERTS+=("$pollution_emoji Hazardous (AQI $AQI, PM2.5: $PM25 µg/m³) → $pollution_advice")
                save_alert_state "pollution_$pollution_level" "$AQI"
                ;;
        esac
    fi

    if [[ "$pressure_alert" == "1" ]] && should_alert "pressure_$pressure_level" "$PRESSURE_IN" "0.1"; then
        case "$pressure_level" in
            "very_low") 
                ALERTS+=("$pressure_emoji Very low pressure ($PRESSURE_IN inHg) → $pressure_advice")
                save_alert_state "pressure_$pressure_level" "$PRESSURE_IN"
                ;;
            "low") 
                ALERTS+=("$pressure_emoji Low pressure ($PRESSURE_IN inHg) → $pressure_advice")
                save_alert_state "pressure_$pressure_level" "$PRESSURE_IN"
                ;;
            "very_high")
                ALERTS+=("$pressure_emoji Very high pressure ($PRESSURE_IN inHg) → $pressure_advice")
                save_alert_state "pressure_$pressure_level" "$PRESSURE_IN"
                ;;
            "high")
                ALERTS+=("$pressure_emoji High pressure ($PRESSURE_IN inHg) → $pressure_advice")
                save_alert_state "pressure_$pressure_level" "$PRESSURE_IN"
                ;;
        esac
    fi

    # Special condition alerts
    [[ "$CONDITION" =~ [Tt]hunder|[Ll]ightning|[Ss]torm ]] && should_alert "thunderstorm" "1" "0" && {
        ALERTS+=("⚡ Thunderstorm detected → $(give_advice thunderstorm)")
        save_alert_state "thunderstorm" "1"
    }

    [[ "$CONDITION" =~ [Ff]og ]] && should_alert "fog" "1" "0" && {
        ALERTS+=("🌫 Fog detected → $(give_advice fog)")
        save_alert_state "fog" "1"
    }

    [[ "$CONDITION" =~ [Ss]now ]] && should_alert "snow" "1" "0" && {
        ALERTS+=("❄️ Snow detected → $(give_advice snow)")
        save_alert_state "snow" "1"
    }
    
    log_debug "Generated ${#ALERTS[@]} current condition alerts"
    log_function_exit "${#ALERTS[@]} alerts"
}

process_peak_alerts() {
    log_function_enter
    PEAK_ALERTS=()
    
    # Process today and tomorrow's peak data
    for day_index in 0 1; do
        local day_date=$(echo "$FORECAST" | jq -r ".forecast.forecastday[$day_index].date")
        local peak_data=$(extract_peak_data "$FORECAST" "$day_index")
        
        IFS='|' read -r max_temp max_temp_time min_temp min_temp_time peak_uv uv_hour rain_peak rain_time temp_advice temp_emoji rain_advice rain_emoji uv_advice uv_emoji <<< "$peak_data"
        
        log_debug "Day $day_index ($day_date) peaks - Max: ${max_temp}°C, Min: ${min_temp}°C, UV: $peak_uv, Rain: ${rain_peak}mm"
        
        # Alert for extreme temperature peaks
        if compare_bc "$max_temp >= 38"; then
            local alert_key="peak_temp_${day_date}_max"
            if should_alert "$alert_key" "$max_temp" "2"; then
                PEAK_ALERTS+=("🔥 Peak Heat Alert: ${max_temp}°C at $max_temp_time on $day_date")
                save_alert_state "$alert_key" "$max_temp"
            fi
        fi
        
        if compare_bc "$min_temp <= 0"; then
            local alert_key="peak_temp_${day_date}_min" 
            if should_alert "$alert_key" "$min_temp" "1"; then
                PEAK_ALERTS+=("🥶 Freezing Alert: ${min_temp}°C at $min_temp_time on $day_date")
                save_alert_state "$alert_key" "$min_temp"
            fi
        fi
        
        # Alert for extreme UV
        if compare_bc "$peak_uv >= 8"; then
            local alert_key="peak_uv_${day_date}"
            if should_alert "$alert_key" "$peak_uv" "1"; then
                PEAK_ALERTS+=("🌞 Extreme UV Alert: $peak_uv at $uv_hour on $day_date")
                save_alert_state "$alert_key" "$peak_uv"
            fi
        fi
        
        # Alert for heavy rain
        if compare_bc "$rain_peak >= 20"; then
            local alert_key="peak_rain_${day_date}"
            if should_alert "$alert_key" "$rain_peak" "5"; then
                PEAK_ALERTS+=("🌧️ Heavy Rain Alert: ${rain_peak}mm at $rain_time on $day_date")
                save_alert_state "$alert_key" "$rain_peak"
            fi
        fi
    done
    
    log_debug "Generated ${#PEAK_ALERTS[@]} peak alerts"
    log_function_exit "${#PEAK_ALERTS[@]} alerts"
}

process_astronomy_alerts() {
    log_function_enter
    ASTRONOMY_ALERTS=()
    
    local localtime=$(echo "$FORECAST" | jq -r '.location.localtime' | cut -d' ' -f2)
    local hour=${localtime%:*}
    local minute=${localtime#*:}
    
    # FIXED: Use base-10 conversion to prevent octal interpretation
    local now=$(( (10#$hour) * 60 + (10#$minute) ))

    local sunrise_minutes=$(time_to_minutes "$SUNRISE")
    local sunset_minutes=$(time_to_minutes "$SUNSET")
    local moonrise_minutes=$(time_to_minutes "$MOONRISE")
    local moonset_minutes=$(time_to_minutes "$MOONSET")

    # Sunrise/Sunset alerts
    if (( now >= sunrise_minutes - ALERT_WINDOW && now <= sunrise_minutes )); then
        local alert_key="sunrise_$(date +%Y%m%d)"
        if should_alert "$alert_key" "$now" "0"; then
            ASTRONOMY_ALERTS+=("☀️ Sunrise in ${ALERT_WINDOW}min at $SUNRISE → $(give_advice sunrise)")
            save_alert_state "$alert_key" "$now"
        fi
    elif (( now >= sunset_minutes - ALERT_WINDOW && now <= sunset_minutes )); then
        local alert_key="sunset_$(date +%Y%m%d)"
        if should_alert "$alert_key" "$now" "0"; then
            ASTRONOMY_ALERTS+=("🌇 Sunset in ${ALERT_WINDOW}min at $SUNSET → $(give_advice sunset)")
            save_alert_state "$alert_key" "$now"
        fi
    fi

    # Moonrise/Moonset alerts
    if (( now >= moonrise_minutes - ALERT_WINDOW && now <= moonrise_minutes )); then
        local alert_key="moonrise_$(date +%Y%m%d)"
        if should_alert "$alert_key" "$now" "0"; then
            ASTRONOMY_ALERTS+=("🌙 Moonrise in ${ALERT_WINDOW}min at $MOONRISE → $(give_advice moonrise)")
            save_alert_state "$alert_key" "$now"
        fi
    elif (( now >= moonset_minutes - ALERT_WINDOW && now <= moonset_minutes )); then
        local alert_key="moonset_$(date +%Y%m%d)"
        if should_alert "$alert_key" "$now" "0"; then
            ASTRONOMY_ALERTS+=("🌘 Moonset in ${ALERT_WINDOW}min at $MOONSET → $(give_advice moonset)")
            save_alert_state "$alert_key" "$now"
        fi
    fi

    # Special moon phase alerts
    case "$MOON_PHASE" in
        "Full Moon")
            local alert_key="full_moon_$(date +%Y%m)"
            if should_alert "$alert_key" "1" "0"; then
                ASTRONOMY_ALERTS+=("🌕 Full Moon Tonight → $(give_advice full_moon)")
                save_alert_state "$alert_key" "1"
            fi
            ;;
        "New Moon")
            local alert_key="new_moon_$(date +%Y%m)"
            if should_alert "$alert_key" "1" "0"; then
                ASTRONOMY_ALERTS+=("🌑 New Moon Tonight → $(give_advice new_moon)")
                save_alert_state "$alert_key" "1"
            fi
            ;;
    esac
    
    log_debug "Generated ${#ASTRONOMY_ALERTS[@]} astronomy alerts"
    log_function_exit "${#ASTRONOMY_ALERTS[@]} alerts"
}

# ------------------------
# Notification System
# ------------------------
send_notifications() {
    log_function_enter
    
    # Generate all types of alerts
    generate_alerts
    process_peak_alerts
    process_astronomy_alerts

    MESSAGE=""
    
    # Combine all alerts
    local ALL_ALERTS=("${ALERTS[@]}" "${PEAK_ALERTS[@]}" "${ASTRONOMY_ALERTS[@]}")
    
    if [[ ${#ALL_ALERTS[@]} -gt 0 ]]; then
        MESSAGE+="🚨 Weather Alerts:\n"
        for a in "${ALL_ALERTS[@]}"; do
            MESSAGE+="• $a\n"
        done
        MESSAGE+="\n"
        log_info "Sending ${#ALL_ALERTS[@]} total alerts to user"
        
        # Send desktop notifications for critical alerts
        for alert in "${ALL_ALERTS[@]}"; do
            if [[ "$alert" =~ 🔥|🥶|🌪|⛈|☠️ ]]; then  # Critical emojis
                if command -v notify-send >/dev/null 2>&1; then
                    notify-send "Weather Alert" "$alert" -u critical -t 10000 2>/dev/null ||
                    log_warn "Desktop notification failed for: $alert"
                fi
            fi
        done
    else
        MESSAGE+="✅ No weather alerts at this time.\n\n"
        log_info "No weather alerts to send"
    fi

    # Get current assessments for display (FIXED - no recursion)
    local current_temp=$(get_weather_metrics temperature "$TEMP_C" "°C")
    local current_humidity=$(get_weather_metrics humidity "$HUMIDITY" "%")
    local current_wind=$(get_weather_metrics wind "$WIND_KPH" "km/h")
    local current_rain=$(get_weather_metrics rain "$PRECIP" "mm")
    local current_uv=$(get_weather_metrics uv "$UV" "")
    local current_pressure=$(get_weather_metrics pressure "$PRESSURE_IN" "inHg")
    local current_pollution=$(get_weather_metrics pollution "$AQI" "")
    local current_visibility=$(get_weather_metrics visibility "$VIS" "km")

    MESSAGE+="📊 Current ($CITY: $LAT, $LON):\n"
    MESSAGE+="• 🌡 Temp: $TEMP_C°C (Feels: $FEELS°C) → $(echo "$current_temp" | cut -d'|' -f2) $(echo "$current_temp" | cut -d'|' -f3)\n"
    MESSAGE+="• 💧 Humidity: $HUMIDITY% → $(echo "$current_humidity" | cut -d'|' -f2) $(echo "$current_humidity" | cut -d'|' -f3)\n"
    MESSAGE+="• 💨 Wind: $WIND_KPH km/h ($WIND_DIR) → $(echo "$current_wind" | cut -d'|' -f2) $(echo "$current_wind" | cut -d'|' -f3)\n"
    MESSAGE+="• 🌧 Rain: $PRECIP mm → $(echo "$current_rain" | cut -d'|' -f2) $(echo "$current_rain" | cut -d'|' -f3)\n"
    MESSAGE+="• 🌞 UV: $UV → $(echo "$current_uv" | cut -d'|' -f2) $(echo "$current_uv" | cut -d'|' -f3)\n"
    MESSAGE+="• 📊 Pressure: $PRESSURE_IN inHg → $(echo "$current_pressure" | cut -d'|' -f2) $(echo "$current_pressure" | cut -d'|' -f3)\n"
    MESSAGE+="• 🌫 Air Quality: AQI $AQI (PM2.5: $PM25 µg/m³) → $(echo "$current_pollution" | cut -d'|' -f2) $(echo "$current_pollution" | cut -d'|' -f3)\n"
    MESSAGE+="• 👁 Visibility: $VIS km → $(echo "$current_visibility" | cut -d'|' -f2) $(echo "$current_visibility" | cut -d'|' -f3)\n\n"

    MESSAGE+="📅 Upcoming Hours Forecast:\n"
    LOCAL_HOUR=$(echo "$FORECAST" | jq -r '.location.localtime' | cut -d' ' -f2 | cut -d: -f1)
    for i in {1..3}; do
        # FIXED: Use base-10 conversion to prevent octal interpretation
        idx=$(( (10#$LOCAL_HOUR) + i ))
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
        
        local hr_rain_assessment=$(get_weather_metrics rain "$hr_rain" "mm")
        local hr_rain_advice=$(echo "$hr_rain_assessment" | cut -d'|' -f2)
        local hr_rain_emoji=$(echo "$hr_rain_assessment" | cut -d'|' -f3)

        MESSAGE+="• $hr_time → $hr_temp°C, $hr_rain mm, $hr_pressure inHg"
        [[ -n "$hr_rain_advice" ]] && MESSAGE+=" → $hr_rain_advice $hr_rain_emoji"
        MESSAGE+="\n"
    done

    # Add peak data to the display
    MESSAGE+="\n📅 Next 2 Days Peak Forecast:\n"
    for i in 0 1; do
        day_date=$(echo "$FORECAST" | jq -r ".forecast.forecastday[$i].date")
        local peak_data=$(extract_peak_data "$FORECAST" "$i")
        IFS='|' read -r max_temp max_temp_time min_temp min_temp_time peak_uv uv_hour rain_peak rain_time temp_advice temp_emoji rain_advice rain_emoji uv_advice uv_emoji <<< "$peak_data"

        MESSAGE+="• $day_date:\n"
        MESSAGE+="  - 🌡 Max: ${max_temp}°C at $max_temp_time $temp_emoji\n"
        MESSAGE+="  - 🌡 Min: ${min_temp}°C at $min_temp_time $temp_emoji\n"
        MESSAGE+="  - 🌞 UV: ${peak_uv} at $uv_hour $uv_emoji\n"
        MESSAGE+="  - 🌧 Rain: ${rain_peak}mm at $rain_time $rain_emoji\n\n"
    done

    MESSAGE+="🌌 Astronomy:\n"
    MESSAGE+="🌅 Sunrise: $SUNRISE | 🌇 Sunset: $SUNSET\n"
    MESSAGE+="🌙 Moonrise: $MOONRISE | 🌘 Moonset: $MOONSET\n"
    MESSAGE+="🌔 Moon Phase: $MOON_PHASE\n"
    
    # Send the main notification
    local current_time_12hr=$(date +"%I:%M %p")
    log_info "Sending comprehensive notification for $CITY at $current_time_12hr"
    
    if command -v kdialog >/dev/null 2>&1; then
        kdialog --title "Weather Update - $CITY ($current_time_12hr)" --msgbox "$MESSAGE" 2>/dev/null ||
        log_warn "KDialog notification failed"
    else
        echo -e "Weather Update - $CITY ($current_time_12hr)\n\n$MESSAGE"
    fi
    
    echo -e "$(date): Weather Update\n$MESSAGE" >> "$LOG_FILE"
    log_function_exit "success"
}

# ------------------------
# Main execution workflow
# ------------------------
fetch_and_process_weather() {
    log_function_enter
    
    if ! get_location; then
        log_error "Location detection failed"
        return 1
    fi
    
    if ! get_weather; then
        log_error "Weather data fetch failed"
        return 1
    fi
    
    if ! send_notifications; then
        log_error "Notification failed"
        return 1
    fi
    
    log_function_exit "success"
    return 0
}

main() {
    log_info "Starting weather monitoring script"
    
    if ! initialize_script; then
        log_error "Failed to initialize script"
        exit 1
    fi
    
    local consecutive_failures=0
    while true; do
        if fetch_and_process_weather; then
            consecutive_failures=0
            log_info "Weather update completed successfully, sleeping for $INTERVAL seconds"
            sleep "$INTERVAL"
        else
            ((consecutive_failures++))
            log_error "Weather update failed (attempt $consecutive_failures)"
            
            if [[ $consecutive_failures -ge 5 ]]; then
                log_error "Too many consecutive failures, exiting"
                exit 1
            fi
            sleep 300  # 5 minutes before retry
        fi
    done
}

# ------------------------
# Script Entry Point
# ------------------------
if [[ "$1" == "--setup" ]]; then
    log_info "Setup mode activated"
    echo "Weather Alarm Script Setup"
    echo "=========================="
    echo "1. API key should be set in ~/.bashrc as:"
    echo "   export WEATHER_API_KEY='your_key_here'"
    echo ""
    echo "2. Log level can be set with:"
    echo "   export WEATHER_LOG_LEVEL=0 (DEBUG) to 3 (ERROR)"
    echo ""
    echo "3. Log file can be set with:"
    echo "   export WEATHER_LOG_FILE='/path/to/log.txt'"
    echo ""
    echo "4. Run normally: ./weather_script.sh"
    echo "   Run in debug: ./weather_script.sh --debug"
    exit 0
fi

if [[ "$1" == "--debug" ]]; then
    export WEATHER_LOG_LEVEL=0
    log_info "Debug mode activated - maximum logging enabled"
fi

if [[ "$1" == "--test" ]]; then
    echo "Testing weather script components..."
    export WEATHER_LOG_LEVEL=0
    initialize_script && get_location && get_weather && send_notifications
    exit $?
fi

# Start the main script
main "$@"
