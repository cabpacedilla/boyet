#!/usr/bin/env bash
export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
# Weather Alarm Script v3.4
# Dependencies:
#   Required: curl, jq, bc, flock, sha256sum, timeout
#   Optional: notify-send (desktop), kdialog (KDE popup), secret-tool (keyring)
# Setup:
#   export WEATHER_API_KEY="your_key" in ~/.bashrc
#
# v3.4 changes over v3.3.2:
#   - API key kept out of curl argv via `curl -K -` (config on stdin)
#   - WeatherAPI error classification (retryable vs. non-retryable)
#   - Government alerts (alerts=yes) normalized into internal severity model
#   - Peak-forecast alerts escalate to `critical` at very extreme values
#   - State pruning uses stored .time rather than parsing dates from keys,
#     so government-alert entries (hash-based keys) do not accumulate forever
#   - Forecast schema requires >=24 hourly entries per day (matching code)
#   - Single validated LOCAL_DATETIME/LOCAL_HOUR/LOCAL_MINUTE, used everywhere
#   - umask 077 for credential/state/cache hygiene
#   - Government-alert dedup includes headline/instruction/desc content
#
# Local modifications:
#   - kdialog uses --msgbox (modal, OK button) instead of --passivepopup
#   - CRITICAL notify-send popups now fire BEFORE kdialog opens (right after
#     email + state commit), not after. kdialog --msgbox is modal and blocks
#     until dismissed or its timeout expires; firing the critical popup
#     first means it is visible immediately instead of being delayed behind
#     (or appearing right as the user dismisses) the modal box.
#   - Location detection uses the pre-v3.4 chain:
#       ip-api.com (HTTP)  ->  ipapi.co (HTTPS)  ->  Nominatim reverse
#     i.e. no location cache / TTL / stale sentinel.
#   - Email uses the pre-v3.4 mechanism:
#       * ALERT_EMAIL is a fixed value (cabpacedilla@gmail.com)
#       * no EMAIL_ENABLED gate
#       * email_trigger state key = alert count; direct save_alert_state
#       * send_email_alert uses `echo -e "$body"` and logs only

umask 077

# ============================================================
# EARLY PATHS AND LOG LEVEL
# ============================================================
LOG_FILE="${WEATHER_LOG_FILE:-$HOME/scriptlogs/weather_alarm.log}"
LOCK_DIR="$HOME/.cache"

LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3
LOG_LEVEL=${WEATHER_LOG_LEVEL:-$LOG_LEVEL_INFO}

if ! [[ "$LOG_LEVEL" =~ ^[0-3]$ ]]; then
    echo "ERROR: Invalid WEATHER_LOG_LEVEL: '$LOG_LEVEL' (must be 0-3)" >&2
    exit 1
fi

if ! mkdir -p "$HOME/scriptlogs" "$LOCK_DIR"; then
    echo "ERROR: Cannot create required directories ($HOME/scriptlogs, $LOCK_DIR)" >&2
    exit 1
fi

# ============================================================
# SINGLE-INSTANCE LOCK
# ============================================================
#~ LOCK_FILE="$LOCK_DIR/weather_alarm.lock"
#~ exec 9>"${LOCK_FILE}"
#~ if ! flock -n 9; then
    #~ echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Another instance is already running. Exiting." >> "$LOG_FILE"
    #~ exit 1
#~ fi

#~ echo $$ > "$LOCK_FILE"

#~ cleanup() {
    #~ local ec=$?
    #~ if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        #~ rm -f "$LOCK_FILE"
    #~ fi
    #~ flock -u 9
    #~ exec 9>&-
    #~ if declare -f log_info >/dev/null 2>&1; then
        #~ log_info "SCRIPT EXITING (code=$ec)"
    #~ else
        #~ echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] SCRIPT EXITING (code=$ec)" >> "$LOG_FILE"
    #~ fi
#~ }

#~ trap cleanup EXIT

# ============================================================
# STATE AND EMAIL PATHS
# ============================================================
ALERT_STATE_FILE="$HOME/.cache/weather_alarm_state.json"
# Email: matches the previous version — fixed address, no env override.
ALERT_EMAIL="cabpacedilla@gmail.com"

if ! mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$ALERT_STATE_FILE")"; then
    echo "ERROR: Cannot create log/state directories ($(dirname "$LOG_FILE"), $(dirname "$ALERT_STATE_FILE"))" >&2
    exit 1
fi

# ------------------------
# Log Rotation
# ------------------------
setup_log_rotation() {
    local max_size=500000

    if [[ -f "$LOG_FILE" ]] && (( $(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) > max_size )); then
        log_info "Rotating log file (size exceeded ${max_size} bytes)"
        mv "$LOG_FILE" "${LOG_FILE}.$(date +%Y%m%d_%H%M%S_%N)" 2>/dev/null || true
        touch "$LOG_FILE"
        ls -1t "$LOG_FILE".[0-9]* 2>/dev/null | tail -n +6 | xargs -r rm -- 2>/dev/null || true
    fi
}

# ------------------------
# Logging
# ------------------------
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local level_str=""

    case "$level" in
        $LOG_LEVEL_DEBUG) level_str="DEBUG" ;;
        $LOG_LEVEL_INFO) level_str="INFO" ;;
        $LOG_LEVEL_WARN) level_str="WARN" ;;
        $LOG_LEVEL_ERROR) level_str="ERROR" ;;
        *) level_str="UNKNOWN" ;;
    esac

    local log_entry="[$timestamp] [$level_str] $message"

    if [[ $level -ge $LOG_LEVEL_WARN ]] || [[ $LOG_LEVEL -eq $LOG_LEVEL_DEBUG ]]; then
        printf '%s\n' "$log_entry" >&2
    fi

    printf '%s\n' "$log_entry" >> "$LOG_FILE"
}

log_debug() { log $LOG_LEVEL_DEBUG "$1"; }
log_info() { log $LOG_LEVEL_INFO "$1"; }
log_warn() { log $LOG_LEVEL_WARN "$1"; }
log_error() { log $LOG_LEVEL_ERROR "$1"; }

log_function_enter() { log_debug "ENTER: ${FUNCNAME[1]} - Args: $*"; }
log_function_exit() { log_debug "EXIT: ${FUNCNAME[1]} - Return: $1"; }
log_variable() { log_debug "VAR: $1 = '$2'"; }
log_api_call() { log_debug "API CALL: $1"; }
log_api_response() { log_debug "API RESPONSE: ${1:0:200}..."; }

# ============================================================
# SEVERITY HELPERS
# ============================================================
alert_severity() {
    printf '%s' "${1%%|*}"
}
alert_text() {
    printf '%s' "${1#*|}"
}

# ============================================================
# ALERT STATE MANAGEMENT
# ============================================================
declare -a PENDING_STATE_KEYS=()
declare -a PENDING_STATE_VALUES=()

queue_state_write() {
    PENDING_STATE_KEYS+=("$1")
    PENDING_STATE_VALUES+=("$2")
}

commit_pending_state_writes() {
    local failures=0 successes=0
    local total=${#PENDING_STATE_KEYS[@]}
    local i
    for (( i=0; i<total; i++ )); do
        if save_alert_state "${PENDING_STATE_KEYS[$i]}" "${PENDING_STATE_VALUES[$i]}"; then
            ((successes++))
        else
            ((failures++))
        fi
    done
    PENDING_STATE_KEYS=()
    PENDING_STATE_VALUES=()

    if (( failures > 0 )); then
        log_error "Committed $successes/$total pending state writes ($failures failed)"
        return 1
    fi
    if (( total > 0 )); then
        log_debug "Committed $total/$total pending state writes"
    fi
    return 0
}

save_alert_state() {
    local alert_type="$1"
    local value="$2"
    local timestamp
    timestamp=$(date +%s)

    local current_state="{}"

    if [[ -f "$ALERT_STATE_FILE" ]]; then
        if ! jq -e . "$ALERT_STATE_FILE" >/dev/null 2>&1; then
            local quarantine="${ALERT_STATE_FILE}.corrupt.$(date +%Y%m%d_%H%M%S_%N)"
            log_warn "Alert state is not valid JSON; quarantining to $quarantine"
            if ! mv "$ALERT_STATE_FILE" "$quarantine" 2>/dev/null; then
                log_error "Could not quarantine corrupted state file; leaving it untouched"
                return 1
            fi
        else
            current_state=$(cat "$ALERT_STATE_FILE" 2>/dev/null || echo "{}")
        fi
    fi

    local new_state
    new_state=$(printf '%s' "$current_state" | jq \
        --arg k "$alert_type" \
        --arg v "$value" \
        --argjson t "$timestamp" \
        '.[$k] = {value: $v, time: $t}' 2>/dev/null)

    if [[ -z "$new_state" || "$new_state" == "null" ]]; then
        log_error "Failed to update alert state for '$alert_type' (jq error)"
        return 1
    fi

    local tmp
    tmp=$(mktemp "${ALERT_STATE_FILE}.XXXXXX") || {
        log_error "Failed to create temp file for alert state"
        return 1
    }
    if ! printf '%s\n' "$new_state" > "$tmp"; then
        log_error "Failed to write temp alert state file"
        rm -f "$tmp"; return 1
    fi
    if ! mv -f "$tmp" "$ALERT_STATE_FILE"; then
        log_error "Failed to replace alert state file"
        rm -f "$tmp"; return 1
    fi
    return 0
}

prune_alert_state() {
    local retention_days="${1:-90}"
    [[ ! -f "$ALERT_STATE_FILE" ]] && return 0

    if ! jq -e . "$ALERT_STATE_FILE" >/dev/null 2>&1; then
        return 0
    fi

    local cutoff
    cutoff=$(( $(date +%s) - retention_days * 86400 ))

    local tmp before after
    tmp=$(mktemp "${ALERT_STATE_FILE}.XXXXXX") || return 1

    if ! jq --argjson cutoff "$cutoff" '
        to_entries
        | map(
            select(
                (.value.time | type) == "number"
                and .value.time >= $cutoff
            )
          )
        | from_entries
    ' "$ALERT_STATE_FILE" > "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        return 1
    fi

    before=$(jq -r 'length' "$ALERT_STATE_FILE" 2>/dev/null || echo 0)
    after=$(jq -r 'length' "$tmp" 2>/dev/null || echo 0)

    if ! mv -f "$tmp" "$ALERT_STATE_FILE"; then
        log_error "Failed to replace alert state after pruning"
        rm -f "$tmp"
        return 1
    fi

    if [[ "$before" -gt "$after" ]]; then
        log_info "Pruned alert state: $before → $after entries (retention ${retention_days}d)"
    fi
    return 0
}

should_alert() {
    local alert_type="$1"
    local current_value="$2"
    local threshold="${3:-0}"
    local timeout="${4:-3600}"

    if [[ -z "$current_value" ]]; then
        log_debug "No current value for '$alert_type'; suppressing alert"
        return 1
    fi

    threshold=${threshold:-0}

    if [[ ! -f "$ALERT_STATE_FILE" ]]; then
        return 0
    fi

    local state
    state=$(cat "$ALERT_STATE_FILE" 2>/dev/null || echo "{}")
    [[ -z "$state" ]] && state="{}"

    local last_value last_time
    last_value=$(printf '%s' "$state" | jq -r --arg k "$alert_type" '.[$k].value // ""' 2>/dev/null)
    last_time=$(printf '%s' "$state" | jq -r --arg k "$alert_type" '.[$k].time // ""' 2>/dev/null)

    if [[ -z "$last_value" ]]; then
        return 0
    fi

    if ! [[ "$last_time" =~ ^[0-9]+$ ]]; then
        log_warn "Corrupted last_time for '$alert_type'; re-alerting"
        return 0
    fi

    local now time_diff
    now=$(date +%s)
    time_diff=$(( now - last_time ))

    if (( threshold == 0 )); then
        if [[ "$current_value" != "$last_value" ]]; then
            return 0
        fi
        if (( timeout > 0 && time_diff > timeout )); then
            return 0
        fi
        return 1
    fi

    if ! [[ "$current_value" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || \
       ! [[ "$last_value" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        if [[ "$current_value" != "$last_value" ]]; then
            return 0
        fi
        if (( timeout > 0 && time_diff > timeout )); then
            return 0
        fi
        return 1
    fi

    local abs_diff
    abs_diff=$(echo "scale=4; d = $current_value - $last_value; if (d < 0) -d else d" | bc -l 2>/dev/null || echo 0)

    if (( $(echo "$abs_diff >= $threshold" | bc -l 2>/dev/null || echo 0) )); then
        return 0
    fi

    if (( timeout > 0 && time_diff > timeout )); then
        return 0
    fi

    return 1
}

# ============================================================
# CONFIGURATION AND DEPENDENCIES
# ============================================================
require_command() {
    local cmd="$1"
    local level="${2:-required}"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        if [[ "$level" == "required" ]]; then
            log_error "Required command not found: $cmd"
            return 1
        else
            log_warn "Optional command not found: $cmd (feature will degrade)"
            return 2
        fi
    fi
    return 0
}

initialize_script() {
    log_function_enter

    local missing=0
    for cmd in curl jq bc flock sha256sum timeout; do
        require_command "$cmd" "required" || missing=1
    done
    if (( missing )); then
        log_error "One or more required dependencies are missing. Aborting."
        return 1
    fi

    require_command msmtp "optional" || true
    require_command notify-send "optional" || true
    require_command kdialog "optional" || true
    require_command secret-tool "optional" || true

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

    if [[ -z "$API_KEY" ]]; then
        log_error "API key is empty"
        return 1
    fi

    if [[ ${#API_KEY} -lt 20 ]]; then
        log_warn "API key seems too short; double check it."
    fi

    BASE_URL="https://api.weatherapi.com/v1"
    INTERVAL=1800
    ALERT_WINDOW=30

    log_debug "Configuration loaded: BASE_URL=$BASE_URL, INTERVAL=$INTERVAL, ALERT_WINDOW=$ALERT_WINDOW"
    log_function_exit "success"
    return 0
}

# ============================================================
# UTILITIES
# ============================================================
compare_bc() {
    local expression="$1"
    [[ -z "$expression" ]] && return 1
    local result
    result=$(echo "$expression" | bc -l 2>/dev/null || echo "0")
    [[ "$result" == "1" ]]
}

safe_extract_value() {
    local json="$1"
    local path="$2"
    local value
    value=$(echo "$json" | jq -r "$path // empty" 2>/dev/null)
    if [[ -z "$value" || "$value" == "null" ]]; then
        echo ""
    else
        echo "$value"
    fi
}

format_metric() {
    local value="$1"
    local suffix="${2:-}"
    if [[ -z "$value" ]]; then
        echo "N/A"
    else
        echo "${value}${suffix}"
    fi
}

curl_secret_url() {
    local url="$1"; shift
    local escaped="${url//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    printf 'url = "%s"\n' "$escaped" | curl -K - "$@"
}

deg_to_dir() {
    log_function_enter "$1"
    local deg="$1"

    if ! [[ "$deg" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        log_function_exit "Unknown"
        echo "Unknown"
        return 1
    fi

    local normalized_deg
    normalized_deg=$(echo "scale=0; ($deg + 360) % 360" | bc -l 2>/dev/null)
    if [[ -z "$normalized_deg" ]]; then
        log_function_exit "Unknown"
        echo "Unknown"
        return 1
    fi

    local directions=("N" "NNE" "NE" "ENE" "E" "ESE" "SE" "SSE"
                      "S" "SSW" "SW" "WSW" "W" "WNW" "NW" "NNW")
    local idx
    idx=$(echo "scale=0; ($normalized_deg + 11.25) / 22.5" | bc -l 2>/dev/null)
    idx=${idx%.*}

    if [[ $idx -ge 16 ]]; then
        idx=0
    fi

    local result="${directions[$idx]}"
    log_function_exit "$result"
    echo "$result"
}

time_to_minutes() {
    log_function_enter "$1"
    local time_str="$1"
    local hour minute

    [[ -z "$time_str" ]] && {
        log_function_exit "0"; echo "0"; return 1
    }

    if [[ ! "$time_str" =~ (AM|PM|am|pm) ]]; then
        hour=$(echo "$time_str" | cut -d: -f1 | sed 's/^0*//')
        minute=$(echo "$time_str" | cut -d: -f2 | sed 's/^0*//')
        [[ ! "$hour" =~ ^[0-9]+$ ]] && { log_function_exit "0"; echo "0"; return 1; }
        [[ ! "$minute" =~ ^[0-9]+$ ]] && { log_function_exit "0"; echo "0"; return 1; }
        [[ $((10#$hour)) -gt 23 ]] && { log_function_exit "0"; echo "0"; return 1; }
        [[ $((10#$minute)) -gt 59 ]] && { log_function_exit "0"; echo "0"; return 1; }
        local result=$(( (10#$hour) * 60 + (10#$minute) ))
        log_function_exit "$result"
        echo $result
        return 0
    fi

    hour=$(echo "$time_str" | cut -d: -f1 | sed 's/^0*//')
    minute=$(echo "$time_str" | cut -d: -f2 | sed 's/[^0-9]//g')
    [[ ! "$hour" =~ ^[0-9]+$ ]] && { log_function_exit "0"; echo "0"; return 1; }
    [[ ! "$minute" =~ ^[0-9]+$ ]] && { log_function_exit "0"; echo "0"; return 1; }
    [[ $((10#$hour)) -gt 12 || $((10#$hour)) -lt 1 ]] && { log_function_exit "0"; echo "0"; return 1; }
    [[ $((10#$minute)) -gt 59 ]] && { log_function_exit "0"; echo "0"; return 1; }

    if [[ "$time_str" =~ (AM|am) ]]; then
        [[ $hour -eq 12 ]] && hour=0
    elif [[ "$time_str" =~ (PM|pm) ]]; then
        [[ $hour -ne 12 ]] && hour=$((hour + 12))
    fi

    local result=$(( (10#$hour) * 60 + (10#$minute) ))
    log_function_exit "$result"
    echo $result
}

format_time_12hr() {
    log_function_enter "$1"
    local time_24hr="$1"
    local hour minute ampm

    hour=$(echo "$time_24hr" | cut -d: -f1 | sed 's/^0*//')
    minute=$(echo "$time_24hr" | cut -d: -f2 | sed 's/^0*//')
    hour=${hour:-0}
    minute=${minute:-0}

    if [[ $hour -eq 0 ]]; then
        hour=12; ampm="AM"
    elif [[ $hour -eq 12 ]]; then
        ampm="PM"
    elif [[ $hour -gt 12 ]]; then
        hour=$((hour - 12)); ampm="PM"
    else
        ampm="AM"
    fi

    minute=$(printf "%02d" "$((10#$minute))")
    local result="${hour}:${minute} ${ampm}"
    log_function_exit "$result"
    echo "$result"
}

check_api_response() {
    local response="$1"
    local endpoint="$2"
    log_function_enter "$endpoint"

    if [[ -z "$response" || "$response" == "null" ]]; then
        log_error "Empty or null response from $endpoint API"
        log_function_exit "1"
        return 1
    fi

    if [[ ! "$response" =~ ^[[:space:]]*\{ ]] && [[ ! "$response" =~ ^[[:space:]]*\[ ]]; then
        log_error "Non-JSON response from $endpoint API: ${response:0:100}..."
        log_function_exit "1"
        return 1
    fi

    if ! echo "$response" | jq -e . >/dev/null 2>&1; then
        log_error "Invalid JSON structure from $endpoint API"
        log_function_exit "1"
        return 1
    fi

    local err_code err_msg
    err_code=$(echo "$response" | jq -r '.error.code // empty' 2>/dev/null)
    err_msg=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)

    if [[ -n "$err_msg" ]]; then
        case "$err_code" in
            1006)
                log_error "API Location Error ($endpoint, code $err_code): $err_msg"
                log_function_exit "2"
                return 2
                ;;
            2006|2007|2008|2009|9007)
                log_error "API Auth/Quota Error ($endpoint, code $err_code): $err_msg"
                log_function_exit "2"
                return 2
                ;;
            *)
                log_error "API Error ($endpoint, code $err_code): $err_msg (treating as retryable)"
                log_function_exit "1"
                return 1
                ;;
        esac
    fi

    log_function_exit "0"
    return 0
}

validate_forecast_schema() {
    local response="$1"
    if ! echo "$response" | jq -e '
        (.location.localtime | type == "string") and
        (.current | type == "object") and
        (.forecast.forecastday | type == "array" and length >= 2) and
        (.forecast.forecastday[0].hour | type == "array" and length >= 24) and
        (.forecast.forecastday[1].hour | type == "array" and length >= 24) and
        (.forecast.forecastday[0].astro | type == "object") and
        (.forecast.forecastday[1].astro | type == "object")
    ' >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Email — matches the previous version's mechanism.
send_email_alert() {
    local subject="$1"
    local body="$2"

    # Use echo -e to interpret \n in the body, same as the previous version.
    {
        echo "To: $ALERT_EMAIL"
        echo "Subject: $subject"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo ""
        echo -e "$body"
    } | msmtp -a default "$ALERT_EMAIL"

    if [[ $? -eq 0 ]]; then
        log_info "Email alert successfully sent to $ALERT_EMAIL"
    else
        log_error "Failed to send email via msmtp. Check your ~/.msmtprc configuration."
    fi
}

# ============================================================
# ADVICE
# ============================================================
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
        "rain_light") advice="Use umbrella" ;;
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

    log_function_exit "$advice"
    echo "$advice"
}

assess_weather() {
    log_function_enter "$1 $2 $3"
    local type="$1" value="$2" unit="$3"
    local level advice emoji alert_threshold=0

    if [[ -z "$value" ]] || ! [[ "$value" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        log_function_exit "unknown"
        echo "unknown|No data|❓|0||$unit"
        return 0
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
    log_function_exit "$result"
    echo "$result"
}

get_weather_metrics() {
    assess_weather "$1" "$2" "$3"
}

validate_coordinates() {
    local coords="$1"

    if [[ ! "$coords" =~ ^-?[0-9]{1,3}\.[0-9]+,-?[0-9]{1,3}\.[0-9]+$ ]]; then
        return 1
    fi

    local lat lon
    lat=$(echo "$coords" | cut -d, -f1)
    lon=$(echo "$coords" | cut -d, -f2)

    if compare_bc "$lat < -90" || compare_bc "$lat > 90"; then
        log_error "Latitude out of range: $lat"
        return 1
    fi

    if compare_bc "$lon < -180" || compare_bc "$lon > 180"; then
        log_error "Longitude out of range: $lon"
        return 1
    fi

    return 0
}

# ============================================================
# LOCATION DETECTION
# ============================================================
# Detection chain (matches the pre-v3.4 behaviour):
#   1. ip-api.com    -> .lat / .lon       (HTTP only; free tier)
#   2. ipapi.co      -> .latitude / .longitude   (HTTPS fallback)
#   3. Nominatim reverse geocoding for the city name
# No cache, no TTL, no stale sentinel.
get_location() {
    log_info "Detecting precise location via IP geolocation..."

    # --- Attempt 1: ip-api.com ---
    local geo_data
    geo_data=$(curl -s --connect-timeout 10 --max-time 20 "http://ip-api.com/json/")
    LAT=$(echo "$geo_data" | jq -r '.lat // empty' 2>/dev/null)
    LON=$(echo "$geo_data" | jq -r '.lon // empty' 2>/dev/null)

    # --- Attempt 2: ipapi.co (Fallback) ---
    if [[ -z "$LAT" || -z "$LON" ]]; then
        log_warn "Primary geo-detection failed. Trying ipapi.co..."
        geo_data=$(curl -s --connect-timeout 10 --max-time 20 "https://ipapi.co/json/")
        LAT=$(echo "$geo_data" | jq -r '.latitude // empty' 2>/dev/null)
        LON=$(echo "$geo_data" | jq -r '.longitude // empty' 2>/dev/null)
    fi

    # --- Validation & Reverse Geocoding ---
    if [[ -n "$LAT" && -n "$LON" ]]; then
        if ! validate_coordinates "$LAT,$LON"; then
            log_error "Invalid coordinates from geolocation service: $LAT,$LON"
            return 1
        fi

        local nominatim_response
        nominatim_response=$(curl -s --connect-timeout 10 --max-time 20 \
            -A "WeatherAlarmScript/1.0 (personal desktop application)" \
            "https://nominatim.openstreetmap.org/reverse?lat=$LAT&lon=$LON&format=json" 2>/dev/null)

        CITY=$(echo "$nominatim_response" | jq -r '.address.city // .address.town // .address.municipality // .address.village // empty' 2>/dev/null)
        if [[ -z "$CITY" || "$CITY" == "null" ]]; then
            CITY="Unknown Location"
            log_warn "Reverse geocoding failed; using Unknown Location"
        fi

        WEATHER_QUERY="$LAT,$LON"
        log_info "Location Found: $CITY ($WEATHER_QUERY)"
        return 0
    fi

    log_error "Critical: Could not detect location from any service."
    return 1
}

# ============================================================
# WEATHER FETCH
# ============================================================
WEATHER_CURL_OPTS=(
  -sS
  --connect-timeout 20
  --max-time 30
  --retry 5
  --retry-delay 5
  --retry-max-time 60
  --compressed
)

get_weather() {
    log_function_enter

    log_api_call "WeatherAPI forecast"
    FORECAST=$(curl_secret_url \
        "$BASE_URL/forecast.json?key=$API_KEY&q=$LAT,$LON&days=2&aqi=yes&alerts=yes" \
        "${WEATHER_CURL_OPTS[@]}")

    check_api_response "$FORECAST" "forecast"
    local api_rc=$?
    if (( api_rc == 2 )); then
        log_error "Non-retryable API error; aborting cycle"
        log_function_exit "non-retryable"
        return 2
    fi
    if (( api_rc != 0 )); then
        log_error "Failed to fetch weather data"
        log_function_exit "retryable"
        return 1
    fi

    if ! validate_forecast_schema "$FORECAST"; then
        log_error "Forecast response schema validation failed"
        log_function_exit "retryable"
        return 1
    fi

    TEMP_C=$(safe_extract_value "$FORECAST" '.current.temp_c')
    FEELS=$(safe_extract_value "$FORECAST" '.current.feelslike_c')
    HUMIDITY=$(safe_extract_value "$FORECAST" '.current.humidity')
    WIND_KPH=$(safe_extract_value "$FORECAST" '.current.wind_kph')
    WIND_DIR_DEG=$(safe_extract_value "$FORECAST" '.current.wind_degree')
    WIND_DIR=$(deg_to_dir "$WIND_DIR_DEG")
    PRECIP=$(safe_extract_value "$FORECAST" '.current.precip_mm')
    UV=$(safe_extract_value "$FORECAST" '.current.uv')
    VIS=$(safe_extract_value "$FORECAST" '.current.vis_km')
    PRESSURE_MB=$(safe_extract_value "$FORECAST" '.current.pressure_mb')
    PRESSURE_IN=$(safe_extract_value "$FORECAST" '.current.pressure_in')
    CONDITION=$(safe_extract_value "$FORECAST" '.current.condition.text')
    AQI=$(safe_extract_value "$FORECAST" '.current.air_quality["us-epa-index"]')
    PM25=$(safe_extract_value "$FORECAST" '.current.air_quality.pm2_5')

    SUNRISE=$(safe_extract_value "$FORECAST" '.forecast.forecastday[0].astro.sunrise')
    SUNSET=$(safe_extract_value "$FORECAST" '.forecast.forecastday[0].astro.sunset')
    MOONRISE=$(safe_extract_value "$FORECAST" '.forecast.forecastday[0].astro.moonrise')
    MOONSET=$(safe_extract_value "$FORECAST" '.forecast.forecastday[0].astro.moonset')
    MOON_PHASE=$(safe_extract_value "$FORECAST" '.forecast.forecastday[0].astro.moon_phase')

    LOCAL_DATETIME=$(safe_extract_value "$FORECAST" '.location.localtime')
    if [[ ! "$LOCAL_DATETIME" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}$ ]]; then
        log_warn "Unexpected .location.localtime format: '$LOCAL_DATETIME'; falling back to system time"
        LOCAL_DATETIME=$(date '+%Y-%m-%d %H:%M')
    fi
    local _local_time="${LOCAL_DATETIME#* }"
    LOCAL_HOUR=$(( 10#${_local_time%%:*} ))
    LOCAL_MINUTE=$(( 10#${_local_time#*:} ))

    log_debug "Extracted: TEMP=$TEMP_C HUM=$HUMIDITY WIND=$WIND_KPH PRECIP=$PRECIP UV=$UV PRES=$PRESSURE_IN AQI=$AQI LOCAL=$LOCAL_DATETIME"
    log_function_exit "success"
    return 0
}

# ============================================================
# PEAK EXTRACTION
# ============================================================
extract_peak_data() {
    log_function_enter "$2"
    local forecast_json="$1"
    local day_index="$2"

    if [[ -z "$forecast_json" || "$forecast_json" == "null" ]]; then
        log_function_exit "fallback"
        echo "|||||||||||||||"
        return 1
    fi

    local day_count
    day_count=$(echo "$forecast_json" | jq -r '.forecast.forecastday | length' 2>/dev/null)
    if [[ "$day_count" -le "$day_index" ]]; then
        log_function_exit "fallback"
        echo "|||||||||||||||"
        return 1
    fi

    local max_temp_data min_temp_data uv_data rain_data
    max_temp_data=$(echo "$forecast_json" | jq -r ".forecast.forecastday[$day_index].hour | [.[] | select(.temp_c != null)] | max_by(.temp_c) | {time: .time, value: .temp_c} // \"\"" 2>/dev/null)
    min_temp_data=$(echo "$forecast_json" | jq -r ".forecast.forecastday[$day_index].hour | [.[] | select(.temp_c != null)] | min_by(.temp_c) | {time: .time, value: .temp_c} // \"\"" 2>/dev/null)
    uv_data=$(echo "$forecast_json" | jq -r ".forecast.forecastday[$day_index].hour | [.[] | select(.uv != null and .uv >= 0)] | max_by(.uv) | {time: .time, value: .uv} // \"\"" 2>/dev/null)
    rain_data=$(echo "$forecast_json" | jq -r ".forecast.forecastday[$day_index].hour | [.[] | select(.precip_mm != null)] | max_by(.precip_mm) | {time: .time, value: .precip_mm} // \"\"" 2>/dev/null)

    local max_temp_value="" max_temp_time="Unknown"
    local min_temp_value="" min_temp_time="Unknown"
    local peak_uv_value="" uv_hour="Unknown"
    local rain_peak="" rain_time="Unknown"

    [[ -n "$max_temp_data" && "$max_temp_data" != "null" ]] && {
        max_temp_value=$(echo "$max_temp_data" | jq -r '.value // empty')
        local t=$(echo "$max_temp_data" | jq -r '.time // ""')
        [[ -n "$t" ]] && max_temp_time=$(echo "$t" | cut -d' ' -f2)
    }

    [[ -n "$min_temp_data" && "$min_temp_data" != "null" ]] && {
        min_temp_value=$(echo "$min_temp_data" | jq -r '.value // empty')
        local t=$(echo "$min_temp_data" | jq -r '.time // ""')
        [[ -n "$t" ]] && min_temp_time=$(echo "$t" | cut -d' ' -f2)
    }

    [[ -n "$uv_data" && "$uv_data" != "null" ]] && {
        peak_uv_value=$(echo "$uv_data" | jq -r '.value // empty')
        local t=$(echo "$uv_data" | jq -r '.time // ""')
        [[ -n "$t" ]] && uv_hour=$(echo "$t" | cut -d' ' -f2)
    }

    [[ -n "$rain_data" && "$rain_data" != "null" ]] && {
        rain_peak=$(echo "$rain_data" | jq -r '.value // empty')
        local t=$(echo "$rain_data" | jq -r '.time // ""')
        [[ -n "$t" ]] && rain_time=$(echo "$t" | cut -d' ' -f2)
    }

    [[ "$max_temp_time" != "Unknown" ]] && max_temp_time=$(format_time_12hr "$max_temp_time" 2>/dev/null || echo "Unknown")
    [[ "$min_temp_time" != "Unknown" ]] && min_temp_time=$(format_time_12hr "$min_temp_time" 2>/dev/null || echo "Unknown")
    [[ "$uv_hour" != "Unknown" ]] && uv_hour=$(format_time_12hr "$uv_hour" 2>/dev/null || echo "Unknown")
    [[ "$rain_time" != "Unknown" ]] && rain_time=$(format_time_12hr "$rain_time" 2>/dev/null || echo "Unknown")

    local max_temp_assessment min_temp_assessment rain_assessment uv_assessment
    max_temp_assessment=$(get_weather_metrics temperature "$max_temp_value" "°C")
    min_temp_assessment=$(get_weather_metrics temperature "$min_temp_value" "°C")
    rain_assessment=$(get_weather_metrics rain "$rain_peak" "mm")
    uv_assessment=$(get_weather_metrics uv "$peak_uv_value" "")

    local max_temp_advice max_temp_emoji min_temp_advice min_temp_emoji
    local rain_advice rain_emoji uv_advice uv_emoji
    max_temp_advice=$(echo "$max_temp_assessment" | cut -d'|' -f2)
    max_temp_emoji=$(echo "$max_temp_assessment" | cut -d'|' -f3)
    min_temp_advice=$(echo "$min_temp_assessment" | cut -d'|' -f2)
    min_temp_emoji=$(echo "$min_temp_assessment" | cut -d'|' -f3)
    rain_advice=$(echo "$rain_assessment" | cut -d'|' -f2)
    rain_emoji=$(echo "$rain_assessment" | cut -d'|' -f3)
    uv_advice=$(echo "$uv_assessment" | cut -d'|' -f2)
    uv_emoji=$(echo "$uv_assessment" | cut -d'|' -f3)

    local result="${max_temp_value}|${max_temp_time}|${min_temp_value}|${min_temp_time}|${peak_uv_value}|${uv_hour}|${rain_peak}|${rain_time}|${max_temp_advice}|${max_temp_emoji}|${min_temp_advice}|${min_temp_emoji}|${rain_advice}|${rain_emoji}|${uv_advice}|${uv_emoji}"

    log_function_exit "success"
    echo "$result"
}

# ============================================================
# ALERT GENERATION
# ============================================================
generate_alerts() {
    log_function_enter
    ALERTS=()

    local temp_assessment rain_assessment wind_assessment uv_assessment
    local pollution_assessment pressure_assessment
    temp_assessment=$(get_weather_metrics temperature "$TEMP_C" "°C")
    rain_assessment=$(get_weather_metrics rain "$PRECIP" "mm")
    wind_assessment=$(get_weather_metrics wind "$WIND_KPH" "km/h")
    uv_assessment=$(get_weather_metrics uv "$UV" "")
    pollution_assessment=$(get_weather_metrics pollution "$AQI" "")
    pressure_assessment=$(get_weather_metrics pressure "$PRESSURE_IN" "inHg")

    local temp_level temp_advice temp_emoji temp_alert
    temp_level=$(echo "$temp_assessment" | cut -d'|' -f1)
    temp_advice=$(echo "$temp_assessment" | cut -d'|' -f2)
    temp_emoji=$(echo "$temp_assessment" | cut -d'|' -f3)
    temp_alert=$(echo "$temp_assessment" | cut -d'|' -f4)

    local rain_level rain_advice rain_emoji rain_alert
    rain_level=$(echo "$rain_assessment" | cut -d'|' -f1)
    rain_advice=$(echo "$rain_assessment" | cut -d'|' -f2)
    rain_emoji=$(echo "$rain_assessment" | cut -d'|' -f3)
    rain_alert=$(echo "$rain_assessment" | cut -d'|' -f4)

    local wind_level wind_advice wind_emoji wind_alert
    wind_level=$(echo "$wind_assessment" | cut -d'|' -f1)
    wind_advice=$(echo "$wind_assessment" | cut -d'|' -f2)
    wind_emoji=$(echo "$wind_assessment" | cut -d'|' -f3)
    wind_alert=$(echo "$wind_assessment" | cut -d'|' -f4)

    local uv_level uv_advice uv_emoji uv_alert
    uv_level=$(echo "$uv_assessment" | cut -d'|' -f1)
    uv_advice=$(echo "$uv_assessment" | cut -d'|' -f2)
    uv_emoji=$(echo "$uv_assessment" | cut -d'|' -f3)
    uv_alert=$(echo "$uv_assessment" | cut -d'|' -f4)

    local pollution_level pollution_advice pollution_emoji pollution_alert
    pollution_level=$(echo "$pollution_assessment" | cut -d'|' -f1)
    pollution_advice=$(echo "$pollution_assessment" | cut -d'|' -f2)
    pollution_emoji=$(echo "$pollution_assessment" | cut -d'|' -f3)
    pollution_alert=$(echo "$pollution_assessment" | cut -d'|' -f4)

    local pressure_level pressure_advice pressure_emoji pressure_alert
    pressure_level=$(echo "$pressure_assessment" | cut -d'|' -f1)
    pressure_advice=$(echo "$pressure_assessment" | cut -d'|' -f2)
    pressure_emoji=$(echo "$pressure_assessment" | cut -d'|' -f3)
    pressure_alert=$(echo "$pressure_assessment" | cut -d'|' -f4)

    if [[ "$temp_level" != "unknown" && "$temp_alert" == "1" ]] && should_alert "temperature_$temp_level" "$TEMP_C" "5"; then
        case "$temp_level" in
            "extreme_heat")
                ALERTS+=("critical|$temp_emoji Extreme heat ($TEMP_C°C) → $temp_advice")
                queue_state_write "temperature_$temp_level" "$TEMP_C"
                ;;
            "extreme_cold")
                ALERTS+=("critical|$temp_emoji Extreme cold ($TEMP_C°C) → $temp_advice")
                queue_state_write "temperature_$temp_level" "$TEMP_C"
                ;;
        esac
    fi

    if [[ "$rain_level" != "unknown" && "$rain_alert" == "1" ]] && should_alert "rain_$rain_level" "$PRECIP" "2"; then
        case "$rain_level" in
            "storm")
                ALERTS+=("critical|$rain_emoji Storm rain ($PRECIP mm) → $rain_advice")
                queue_state_write "rain_$rain_level" "$PRECIP"
                ;;
            "heavy"|"moderate")
                ALERTS+=("warning|$rain_emoji $(echo "$rain_level" | sed 's/^./\U&/') rain ($PRECIP mm) → $rain_advice")
                queue_state_write "rain_$rain_level" "$PRECIP"
                ;;
            "light")
                ALERTS+=("info|$rain_emoji Light rain ($PRECIP mm) → $rain_advice")
                queue_state_write "rain_$rain_level" "$PRECIP"
                ;;
        esac
    fi

    if [[ "$wind_level" != "unknown" && "$wind_alert" == "1" ]] && should_alert "wind_$wind_level" "$WIND_KPH" "10"; then
        case "$wind_level" in
            "storm")
                ALERTS+=("critical|$wind_emoji Storm-force wind ($WIND_KPH km/h) → $wind_advice")
                queue_state_write "wind_$wind_level" "$WIND_KPH"
                ;;
            "strong")
                ALERTS+=("warning|$wind_emoji Strong wind ($WIND_KPH km/h) → $wind_advice")
                queue_state_write "wind_$wind_level" "$WIND_KPH"
                ;;
        esac
    fi

    if [[ "$uv_level" != "unknown" && "$uv_alert" == "1" ]] && should_alert "uv_$uv_level" "$UV" "1"; then
        case "$uv_level" in
            "extreme")
                ALERTS+=("warning|$uv_emoji Extreme UV ($UV) → $uv_advice")
                queue_state_write "uv_$uv_level" "$UV"
                ;;
            "high")
                ALERTS+=("warning|$uv_emoji High UV ($UV) → $uv_advice")
                queue_state_write "uv_$uv_level" "$UV"
                ;;
        esac
    fi

    if [[ "$pollution_level" != "unknown" && "$pollution_alert" == "1" ]] && should_alert "pollution_$pollution_level" "$AQI" "1"; then
        case "$pollution_level" in
            "unhealthy"|"very_unhealthy")
                ALERTS+=("warning|$pollution_emoji $(echo "$pollution_level" | tr '_' ' ') (AQI $AQI, PM2.5: $PM25 µg/m³) → $pollution_advice")
                queue_state_write "pollution_$pollution_level" "$AQI"
                ;;
            "hazardous")
                ALERTS+=("critical|$pollution_emoji Hazardous air (AQI $AQI, PM2.5: $PM25 µg/m³) → $pollution_advice")
                queue_state_write "pollution_$pollution_level" "$AQI"
                ;;
        esac
    fi

    if [[ "$pressure_level" != "unknown" && "$pressure_alert" == "1" ]] && should_alert "pressure_$pressure_level" "$PRESSURE_IN" "0.1"; then
        case "$pressure_level" in
            "very_low"|"low"|"very_high"|"high")
                ALERTS+=("info|$pressure_emoji $(echo "$pressure_level" | tr '_' ' ') pressure ($PRESSURE_IN inHg) → $pressure_advice")
                queue_state_write "pressure_$pressure_level" "$PRESSURE_IN"
                ;;
        esac
    fi

    local today_api
    today_api=$(echo "$FORECAST" | jq -r '.forecast.forecastday[0].date' | tr -d '-')
    [[ -z "$today_api" ]] && today_api=$(date +%Y%m%d)

    [[ "$CONDITION" =~ [Tt]hunder|[Ll]ightning|[Ss]torm ]] && should_alert "thunderstorm" "$today_api" "0" && {
        ALERTS+=("critical|⚡ Thunderstorm detected → $(give_advice thunderstorm)")
        queue_state_write "thunderstorm" "$today_api"
    }

    [[ "$CONDITION" =~ [Ff]og ]] && should_alert "fog" "$today_api" "0" && {
        ALERTS+=("warning|🌫 Fog detected → $(give_advice fog)")
        queue_state_write "fog" "$today_api"
    }

    [[ "$CONDITION" =~ [Ss]now ]] && should_alert "snow" "$today_api" "0" && {
        ALERTS+=("warning|❄️ Snow detected → $(give_advice snow)")
        queue_state_write "snow" "$today_api"
    }

    log_function_exit "${#ALERTS[@]} alerts"
}

process_peak_alerts() {
    log_function_enter
    PEAK_ALERTS=()

    for day_index in 0 1; do
        local day_date peak_data
        day_date=$(echo "$FORECAST" | jq -r ".forecast.forecastday[$day_index].date")
        peak_data=$(extract_peak_data "$FORECAST" "$day_index")

        local max_temp max_temp_time min_temp min_temp_time peak_uv uv_hour rain_peak rain_time
        local max_temp_advice max_temp_emoji min_temp_advice min_temp_emoji rain_advice rain_emoji uv_advice uv_emoji
        IFS='|' read -r max_temp max_temp_time min_temp min_temp_time peak_uv uv_hour rain_peak rain_time \
            max_temp_advice max_temp_emoji min_temp_advice min_temp_emoji rain_advice rain_emoji uv_advice uv_emoji <<< "$peak_data"

        if [[ -n "$max_temp" ]] && compare_bc "$max_temp >= 38"; then
            local alert_key="peak_temp_${day_date}_max"
            if should_alert "$alert_key" "$max_temp" "2"; then
                local sev="warning"
                compare_bc "$max_temp >= 42" && sev="critical"
                PEAK_ALERTS+=("$sev|🔥 Peak Heat Alert: ${max_temp}°C at $max_temp_time on $day_date")
                queue_state_write "$alert_key" "$max_temp"
            fi
        fi

        if [[ -n "$min_temp" ]] && compare_bc "$min_temp <= 0"; then
            local alert_key="peak_temp_${day_date}_min"
            if should_alert "$alert_key" "$min_temp" "1"; then
                local sev="warning"
                compare_bc "$min_temp <= -8" && sev="critical"
                PEAK_ALERTS+=("$sev|🥶 Freezing Alert: ${min_temp}°C at $min_temp_time on $day_date")
                queue_state_write "$alert_key" "$min_temp"
            fi
        fi

        if [[ -n "$peak_uv" ]] && compare_bc "$peak_uv >= 8"; then
            local alert_key="peak_uv_${day_date}"
            if should_alert "$alert_key" "$peak_uv" "1"; then
                local sev="warning"
                compare_bc "$peak_uv >= 11" && sev="critical"
                PEAK_ALERTS+=("$sev|🌞 Extreme UV Alert: $peak_uv at $uv_hour on $day_date")
                queue_state_write "$alert_key" "$peak_uv"
            fi
        fi

        if [[ -n "$rain_peak" ]] && compare_bc "$rain_peak >= 20"; then
            local alert_key="peak_rain_${day_date}"
            if should_alert "$alert_key" "$rain_peak" "5"; then
                local sev="warning"
                compare_bc "$rain_peak >= 50" && sev="critical"
                PEAK_ALERTS+=("$sev|🌧️ Heavy Rain Alert: ${rain_peak}mm at $rain_time on $day_date")
                queue_state_write "$alert_key" "$rain_peak"
            fi
        fi
    done

    log_function_exit "${#PEAK_ALERTS[@]} alerts"
}

check_astronomy_event_for_day() {
    local prefix="$1"
    local day_index="$2"
    local now_min="$3"
    local advice_key="$4"
    local emoji="$5"
    local label="$6"

    local event_time event_date_iso
    event_time=$(echo "$FORECAST" | jq -r ".forecast.forecastday[$day_index].astro.$prefix // empty")
    event_date_iso=$(echo "$FORECAST" | jq -r ".forecast.forecastday[$day_index].date // empty")

    [[ -z "$event_time" || -z "$event_date_iso" ]] && return 0

    local event_min
    if ! event_min=$(time_to_minutes "$event_time"); then
        log_warn "Invalid astronomy time for $prefix (day $day_index): '$event_time'"
        return 0
    fi

    local mins day_qualifier=""
    if (( day_index == 0 )); then
        if (( event_min < now_min )); then
            return 0
        fi
        mins=$(( event_min - now_min ))
    else
        mins=$(( 1440 - now_min + event_min ))
        day_qualifier=" tomorrow"
    fi

    if (( mins > ALERT_WINDOW )); then
        return 0
    fi

    local event_date="${event_date_iso//-/}"
    local alert_key="${prefix}_${event_date}_${event_min}"

    if should_alert "$alert_key" "$event_time" "0" 0; then
        ASTRONOMY_ALERTS+=("info|${emoji} ${label} in ${mins}min at ${event_time}${day_qualifier} → $(give_advice "$advice_key")")
        queue_state_write "$alert_key" "$event_time"
    fi
}

process_astronomy_alerts() {
    log_function_enter
    ASTRONOMY_ALERTS=()

    local now=$(( LOCAL_HOUR * 60 + LOCAL_MINUTE ))

    local local_date_iso local_event_date
    local_date_iso=$(echo "$FORECAST" | jq -r '.forecast.forecastday[0].date')
    local_event_date="${local_date_iso//-/}"

    for day_idx in 0 1; do
        check_astronomy_event_for_day "sunrise"  "$day_idx" "$now" "sunrise"  "☀️"  "Sunrise"
        check_astronomy_event_for_day "sunset"   "$day_idx" "$now" "sunset"   "🌇"  "Sunset"
        check_astronomy_event_for_day "moonrise" "$day_idx" "$now" "moonrise" "🌙"  "Moonrise"
        check_astronomy_event_for_day "moonset"  "$day_idx" "$now" "moonset"  "🌘"  "Moonset"
    done

    case "$MOON_PHASE" in
        "Full Moon")
            local alert_key="full_moon_${local_event_date}"
            if should_alert "$alert_key" "1" "0" 0; then
                ASTRONOMY_ALERTS+=("info|🌕 Full Moon phase today → $(give_advice full_moon)")
                queue_state_write "$alert_key" "1"
            fi
            ;;
        "New Moon")
            local alert_key="new_moon_${local_event_date}"
            if should_alert "$alert_key" "1" "0" 0; then
                ASTRONOMY_ALERTS+=("info|🌑 New Moon phase today → $(give_advice new_moon)")
                queue_state_write "$alert_key" "1"
            fi
            ;;
    esac

    log_function_exit "${#ASTRONOMY_ALERTS[@]} alerts"
}

# ============================================================
# GOVERNMENT WEATHER ALERTS
# ============================================================
process_government_alerts() {
    log_function_enter
    GOV_ALERTS=()

    local alert_count
    alert_count=$(echo "$FORECAST" | jq -r '(.alerts.alert // []) | length' 2>/dev/null)
    [[ -z "$alert_count" || "$alert_count" == "null" ]] && alert_count=0
    if (( alert_count == 0 )); then
        log_function_exit "0 alerts"
        return 0
    fi

    local now_epoch; now_epoch=$(date +%s)

    local i
    for (( i=0; i<alert_count; i++ )); do
        local event severity urgency effective expires headline instruction desc
        event=$(echo "$FORECAST" | jq -r ".alerts.alert[$i].event // empty")
        severity=$(echo "$FORECAST" | jq -r ".alerts.alert[$i].severity // empty")
        urgency=$(echo "$FORECAST" | jq -r ".alerts.alert[$i].urgency // empty")
        effective=$(echo "$FORECAST" | jq -r ".alerts.alert[$i].effective // empty")
        expires=$(echo "$FORECAST" | jq -r ".alerts.alert[$i].expires // empty")
        headline=$(echo "$FORECAST" | jq -r ".alerts.alert[$i].headline // empty")
        instruction=$(echo "$FORECAST" | jq -r ".alerts.alert[$i].instruction // empty")
        desc=$(echo "$FORECAST" | jq -r ".alerts.alert[$i].desc // empty")

        [[ -z "$event" || -z "$severity" ]] && continue

        if [[ -n "$expires" ]]; then
            local exp_epoch
            exp_epoch=$(date -d "$expires" +%s 2>/dev/null) || exp_epoch=0
            if (( exp_epoch > 0 && exp_epoch < now_epoch )); then
                log_debug "Skipping expired gov alert: $event (expired $expires)"
                continue
            fi
        fi
        case "${urgency,,}" in
            past) continue ;;
        esac

        local internal_sev
        case "${severity,,}" in
            extreme|severe) internal_sev="critical" ;;
            moderate)       internal_sev="warning" ;;
            minor)          internal_sev="info" ;;
            *)              internal_sev="warning" ;;
        esac

        local dedup_hash alert_key
        dedup_hash=$(printf '%s|%s|%s|%s|%s|%s|%s|%s' \
            "$event" "$effective" "$expires" "$severity" "$urgency" \
            "$headline" "$instruction" "$desc" \
            | sha256sum | cut -c1-16)
        alert_key="gov_alert_${dedup_hash}"

        if should_alert "$alert_key" "$event" "0" 0; then
            local text="⚠️ [$severity/$urgency] $event"
            [[ -n "$headline" ]] && text="$text — $headline"
            if [[ -n "$instruction" ]]; then
                text="$text → $instruction"
            elif [[ -n "$desc" ]]; then
                local short_desc="${desc:0:200}"
                text="$text → $short_desc"
            fi
            GOV_ALERTS+=("${internal_sev}|$text")
            queue_state_write "$alert_key" "$event"
        fi
    done

    log_function_exit "${#GOV_ALERTS[@]} alerts"
}

# ============================================================
# NOTIFICATIONS
# ============================================================
send_notifications() {
    log_function_enter

    PENDING_STATE_KEYS=()
    PENDING_STATE_VALUES=()

    generate_alerts
    process_peak_alerts
    process_astronomy_alerts
    process_government_alerts

    MESSAGE=""

    local ALL_ALERTS=("${ALERTS[@]}" "${PEAK_ALERTS[@]}" "${ASTRONOMY_ALERTS[@]}" "${GOV_ALERTS[@]}")

    local cycle_ok=true

    if [[ ${#ALL_ALERTS[@]} -gt 0 ]]; then
        ALERT_CONTENT=$'\n🚨 WEATHER ALARMS FOR '"$CITY"$'\n'
        ALERT_CONTENT+="=============================="$'\n'
        local a
        for a in "${ALL_ALERTS[@]}"; do
            ALERT_CONTENT+="• $(alert_text "$a")"$'\n'
        done

        MESSAGE="${ALERT_CONTENT}"

        log_info "Processing ${#ALL_ALERTS[@]} total alerts"

        # Email: previous version's mechanism — email_trigger state key,
        # alert count as value, direct save_alert_state (no queue).
        if should_alert "email_trigger" "${#ALL_ALERTS[@]}" 0; then
            send_email_alert "Weather Alert: ${#ALL_ALERTS[@]} Alarms in $CITY - $(alert_text "${ALL_ALERTS[0]}")" "$MESSAGE"
            save_alert_state "email_trigger" "${#ALL_ALERTS[@]}"
        else
            log_debug "Email suppressed: same alert count as last send"
        fi

        # Commit queued condition state (populated by generate_alerts and friends).
        if [[ ${#PENDING_STATE_KEYS[@]} -gt 0 ]]; then
            if ! commit_pending_state_writes; then
                log_error "Alert state commit failed; some conditions may re-fire next cycle"
                cycle_ok=false
            fi
        fi

        # === Per-alert desktop notifications — fire BEFORE kdialog ===
        # kdialog --msgbox below is modal and blocks until the user clicks
        # OK (or its own timeout kills it). Firing notify-send here,
        # immediately after alerts are known, means each alert is visible
        # right away instead of being delayed behind (or appearing right as
        # the user dismisses) the modal message box.
        #
        # All severities fire a popup, not just "critical" — but the
        # notify-send urgency/title/timeout still reflect that alert's own
        # severity, so a rain warning doesn't masquerade as a critical alert.
        if command -v notify-send >/dev/null 2>&1; then
            for a in "${ALL_ALERTS[@]}"; do
                local a_sev a_title a_urgency a_expire
                a_sev="$(alert_severity "$a")"
                case "$a_sev" in
                    critical)
                        a_title="CRITICAL Weather Alert"
                        a_urgency="critical"
                        a_expire=10000
                        ;;
                    warning)
                        a_title="Weather Warning"
                        a_urgency="normal"
                        a_expire=8000
                        ;;
                    *)
                        a_title="Weather Notice"
                        a_urgency="low"
                        a_expire=6000
                        ;;
                esac
                timeout --kill-after=2 5 notify-send \
                    "$a_title" "$(alert_text "$a")" \
                    -u "$a_urgency" -t "$a_expire" 2>/dev/null \
                    || log_warn "notify-send timed out or failed ($a_sev alert)"
            done
        fi
    else
        PENDING_STATE_KEYS=()
        PENDING_STATE_VALUES=()
    fi

    local current_temp current_humidity current_wind current_rain
    local current_uv current_pressure current_pollution current_visibility
    current_temp=$(get_weather_metrics temperature "$TEMP_C" "°C")
    current_humidity=$(get_weather_metrics humidity "$HUMIDITY" "%")
    current_wind=$(get_weather_metrics wind "$WIND_KPH" "km/h")
    current_rain=$(get_weather_metrics rain "$PRECIP" "mm")
    current_uv=$(get_weather_metrics uv "$UV" "")
    current_pressure=$(get_weather_metrics pressure "$PRESSURE_IN" "inHg")
    current_pollution=$(get_weather_metrics pollution "$AQI" "")
    current_visibility=$(get_weather_metrics visibility "$VIS" "km")

    MESSAGE+=$'\n📊 Current ('"$CITY"': '"$LAT"', '"$LON"$'):\n'
    MESSAGE+="• 🌡 Temp: $(format_metric "$TEMP_C" "°C") (Feels: $(format_metric "$FEELS" "°C")) → $(echo "$current_temp" | cut -d'|' -f2) $(echo "$current_temp" | cut -d'|' -f3)"$'\n'
    MESSAGE+="• 💧 Humidity: $(format_metric "$HUMIDITY" "%") → $(echo "$current_humidity" | cut -d'|' -f2) $(echo "$current_humidity" | cut -d'|' -f3)"$'\n'
    MESSAGE+="• 💨 Wind: $(format_metric "$WIND_KPH" " km/h") ($WIND_DIR) → $(echo "$current_wind" | cut -d'|' -f2) $(echo "$current_wind" | cut -d'|' -f3)"$'\n'
    MESSAGE+="• 🌧 Rain: $(format_metric "$PRECIP" " mm") → $(echo "$current_rain" | cut -d'|' -f2) $(echo "$current_rain" | cut -d'|' -f3)"$'\n'
    MESSAGE+="• 🌞 UV: $(format_metric "$UV" "") → $(echo "$current_uv" | cut -d'|' -f2) $(echo "$current_uv" | cut -d'|' -f3)"$'\n'
    MESSAGE+="• 📊 Pressure: $(format_metric "$PRESSURE_IN" " inHg") → $(echo "$current_pressure" | cut -d'|' -f2) $(echo "$current_pressure" | cut -d'|' -f3)"$'\n'
    MESSAGE+="• 🌫 Air Quality: AQI $(format_metric "$AQI" "") (PM2.5: $(format_metric "$PM25" " µg/m³")) → $(echo "$current_pollution" | cut -d'|' -f2) $(echo "$current_pollution" | cut -d'|' -f3)"$'\n'
    MESSAGE+="• 👁 Visibility: $(format_metric "$VIS" " km") → $(echo "$current_visibility" | cut -d'|' -f2) $(echo "$current_visibility" | cut -d'|' -f3)"$'\n\n'

    MESSAGE+="📅 Upcoming Hours Forecast:"$'\n'
    for i in {1..3}; do
        local idx=$(( LOCAL_HOUR + i ))
        local day=0
        if (( idx > 23 )); then
            idx=$((idx - 24))
            day=1
        fi
        local hr_time_24hr hr_time hr_temp hr_rain hr_pressure
        hr_time_24hr=$(echo "$FORECAST" | jq -r ".forecast.forecastday[$day].hour[$idx].time" | cut -d' ' -f2)
        hr_time=$(format_time_12hr "$hr_time_24hr")
        hr_temp=$(echo "$FORECAST" | jq -r ".forecast.forecastday[$day].hour[$idx].temp_c // empty")
        hr_rain=$(echo "$FORECAST" | jq -r ".forecast.forecastday[$day].hour[$idx].precip_mm // empty")
        hr_pressure=$(echo "$FORECAST" | jq -r ".forecast.forecastday[$day].hour[$idx].pressure_in // empty")

        local hr_rain_assessment hr_rain_advice hr_rain_emoji
        hr_rain_assessment=$(get_weather_metrics rain "$hr_rain" "mm")
        hr_rain_advice=$(echo "$hr_rain_assessment" | cut -d'|' -f2)
        hr_rain_emoji=$(echo "$hr_rain_assessment" | cut -d'|' -f3)

        MESSAGE+="• $hr_time → $(format_metric "$hr_temp" "°C"), $(format_metric "$hr_rain" " mm"), $(format_metric "$hr_pressure" " inHg")"
        [[ -n "$hr_rain_advice" && "$hr_rain_advice" != "No data" ]] && MESSAGE+=" → $hr_rain_advice $hr_rain_emoji"
        MESSAGE+=$'\n'
    done

    MESSAGE+=$'\n📅 Next 2 Days Peak Forecast:\n'
    for i in 0 1; do
        local day_date peak_data
        day_date=$(echo "$FORECAST" | jq -r ".forecast.forecastday[$i].date")
        peak_data=$(extract_peak_data "$FORECAST" "$i")
        local max_temp max_temp_time min_temp min_temp_time peak_uv uv_hour rain_peak rain_time
        local max_temp_advice max_temp_emoji min_temp_advice min_temp_emoji rain_advice rain_emoji uv_advice uv_emoji
        IFS='|' read -r max_temp max_temp_time min_temp min_temp_time peak_uv uv_hour rain_peak rain_time \
            max_temp_advice max_temp_emoji min_temp_advice min_temp_emoji rain_advice rain_emoji uv_advice uv_emoji <<< "$peak_data"

        MESSAGE+="• $day_date:"$'\n'
        MESSAGE+="  - 🌡 Max: $(format_metric "$max_temp" "°C") at $max_temp_time $max_temp_emoji"$'\n'
        MESSAGE+="  - 🌡 Min: $(format_metric "$min_temp" "°C") at $min_temp_time $min_temp_emoji"$'\n'
        MESSAGE+="  - 🌞 UV: $(format_metric "$peak_uv" "") at $uv_hour $uv_emoji"$'\n'
        MESSAGE+="  - 🌧 Rain: $(format_metric "$rain_peak" " mm") at $rain_time $rain_emoji"$'\n\n'
    done

    MESSAGE+="🌌 Astronomy:"$'\n'
    MESSAGE+="🌅 Sunrise: ${SUNRISE:-N/A} | 🌇 Sunset: ${SUNSET:-N/A}"$'\n'
    MESSAGE+="🌙 Moonrise: ${MOONRISE:-N/A} | 🌘 Moonset: ${MOONSET:-N/A}"$'\n'
    MESSAGE+="🌔 Moon Phase: ${MOON_PHASE:-N/A}"$'\n'

    local current_time_12hr
    current_time_12hr=$(date +"%I:%M %p")
    log_info "Sending comprehensive notification for $CITY at $current_time_12hr"

    local notified=false

    if command -v kdialog >/dev/null 2>&1; then
        if timeout --kill-after=2 120 kdialog --title "Weather Update - $CITY ($current_time_12hr)" \
                --msgbox "$MESSAGE" 2>/dev/null; then
            notified=true
        else
            log_debug "KDialog msgbox dismissed, timed out, or failed; falling back to notify-send"
        fi
    fi

    if ! $notified && command -v notify-send >/dev/null 2>&1; then
        if timeout --kill-after=2 5 notify-send -t 60000 "Weather Update - $CITY" "$MESSAGE" 2>/dev/null; then
            notified=true
        else
            log_warn "notify-send failed or timed out"
        fi
    fi

    if ! $notified; then
        printf '%s\n\n%s\n' "Weather Update - $CITY ($current_time_12hr)" "$MESSAGE"
    fi

    printf '%s\n\n%s\n' "$(date): Weather Update" "$MESSAGE" >> "$LOG_FILE"

    if $cycle_ok; then
        log_function_exit "success"
        return 0
    fi
    log_function_exit "failure"
    return 1
}

# ============================================================
# MAIN WORKFLOW
# ============================================================
fetch_and_process_weather() {
    log_function_enter

    if ! get_location; then
        log_error "Location detection failed"
        return 1
    fi

    get_weather
    local weather_rc=$?
    if (( weather_rc == 2 )); then
        log_error "Non-retryable weather fetch failure"
        return 2
    fi
    if (( weather_rc != 0 )); then
        log_error "Weather data fetch failed"
        return 1
    fi

    if ! send_notifications; then
        log_error "Notification/state commit failed"
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
        setup_log_rotation
        prune_alert_state 90
        log_debug "heartbeat (pid=$$)"

        fetch_and_process_weather
        local rc=$?

        if (( rc == 0 )); then
            consecutive_failures=0
            log_info "Weather update completed successfully, sleeping for $INTERVAL seconds"
            sleep "$INTERVAL"
        elif (( rc == 2 )); then
            log_error "Non-retryable error (auth/quota/invalid location); exiting"
            exit 1
        else
            ((consecutive_failures++))
            log_error "Weather update failed (attempt $consecutive_failures)"
            if [[ $consecutive_failures -ge 5 ]]; then
                log_error "Too many consecutive failures, exiting"
                exit 1
            fi
            sleep 300
        fi
    done
}

# ============================================================
# ENTRY POINT
# ============================================================
case "${1:-}" in
    --setup)
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
        echo "4. Run normally: ./weather_alarm.sh"
        echo "   Run in debug: ./weather_alarm.sh --debug"
        echo "   Live test:    ./weather_alarm.sh --test-live   (sends real emails,"
        echo "                                                    mutates alert state)"
        exit 0
        ;;
    --debug)
        export WEATHER_LOG_LEVEL=0
        LOG_LEVEL=$LOG_LEVEL_DEBUG
        log_info "Debug mode activated - maximum logging enabled"
        main "$@"
        ;;
    --test-live)
        echo "Testing weather script components (LIVE - will send real notifications and mutate alert state)..."
        export WEATHER_LOG_LEVEL=0
        LOG_LEVEL=$LOG_LEVEL_DEBUG
        initialize_script && get_location && get_weather && send_notifications
        exit $?
        ;;
    "")
        main "$@"
        ;;
    *)
        echo "Unknown argument: $1" >&2
        echo "Usage: $0 [--setup|--debug|--test-live]" >&2
        exit 2
        ;;
esac
Library - Grok
