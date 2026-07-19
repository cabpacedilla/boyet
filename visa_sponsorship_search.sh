#!/usr/bin/env bash
# ============================================================
# Himalayas Job Search - Senior QA/SDET Roles (Semantic Mode)
# VERSION: 2.28 - Production final (frozen)
# ============================================================

# --- IMMUTABLE CONFIGURATION ---
readonly SCRIPT_VERSION="2.28"

set -Euo pipefail

# --- CLI ARGUMENTS ---
RUN_ONCE=false
SHOW_HELP=false
SHOW_VERSION=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--once)   RUN_ONCE=true ; shift ;;
        -h|--help)   SHOW_HELP=true ; shift ;;
        -v|--version) SHOW_VERSION=true ; shift ;;
        --daemon)    shift ;;
        *) echo "Unknown option: $1" >&2 ; exit 1 ;;
    esac
done

if $SHOW_HELP; then
    cat <<EOF
Usage: $0 [OPTION]

Options:
  -o, --once     Run a single search cycle and exit (useful for testing)
  -h, --help     Show this help message
  -v, --version  Show version information
  --daemon       Run as a daemon (default behavior)

Without any options, runs continuously with jittered sleep cycles.
EOF
    exit 0
fi

if $SHOW_VERSION; then
    echo "visa_job_search.sh version ${SCRIPT_VERSION}"
    echo "Himalayas Job Search - Senior QA/SDET Roles (Semantic Mode)"
    exit 0
fi

# --- CONFIGURATION ---
readonly BIN_DIR="$HOME/Documents/bin"
readonly SEEN_FILE="$BIN_DIR/jobs_seen.txt"
readonly LOG_DIR="$HOME/scriptlogs/job_search"
readonly JSON_LOG_FILE="$BIN_DIR/visa_job_search.jsonl"  
readonly HEARTBEAT_FILE="$BIN_DIR/visa_job_engine.heartbeat"
readonly EMAIL_TO="cabpacedilla@gmail.com"
readonly INCLUDE_WORLDWIDE=true

mkdir -p "$LOG_DIR" "$BIN_DIR"
touch "$SEEN_FILE" "$JSON_LOG_FILE"

# --- DEPENDENCY CHECK (only for packages not guaranteed to be present) ---
for cmd in jq curl msmtp flock md5sum; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: Required dependency '$cmd' is not installed. Exiting." >&2
        exit 1
    fi
done

# --- PORTABILITY: Build curl retry arguments (detect --retry-all-errors) ---
CURL_RETRY_ARGS=(
    --retry 3
    --retry-delay 2
    --retry-connrefused
)

# Check both --help and --help all for maximum compatibility
if curl --help 2>/dev/null | grep -q -- '--retry-all-errors' ||
   curl --help all 2>/dev/null | grep -q -- '--retry-all-errors'; then
    CURL_RETRY_ARGS+=(--retry-all-errors)
fi
readonly CURL_RETRY_ARGS

# --- LOCKING ---
readonly LOCK_FILE="/tmp/visa_job_scraper_$(whoami).lock"
exec 9>"$LOCK_FILE"

if ! flock -n 9; then
    echo "$(date): Another instance running, exiting." >&2
    exit 1
fi

printf '%d\n' "$$" > "$LOCK_FILE"

# --- CLEANUP ---
cleanup() {
    # Release the advisory lock first, then remove the informational PID file.
    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
    rm -f "$LOCK_FILE"
}

# --- TRAPS (signal handling for graceful shutdown) ---
trap 'visa_json_log "WARN" "SIGTERM received"; exit 143' TERM
trap 'visa_json_log "WARN" "SIGINT received"; exit 130' INT

# EXIT trap runs cleanup on any exit (normal or error)
trap '
    rc=$?
    if (( rc == 0 )); then
        visa_json_log "INFO" "Normal exit"
    else
        visa_json_log "ERROR" "Exit rc=$rc"
    fi
    cleanup
' EXIT

# ERR trap logs unexpected errors before the EXIT trap runs
trap '
    rc=$?
    visa_json_log "ERROR" "ERR trap rc=$rc line=$LINENO cmd=${BASH_COMMAND@Q}"
' ERR

# ============================================================
# KEYWORDS & CONFIG
# ============================================================
readonly QA_KEYWORDS=(
    "QA" "Quality Assurance" "Quality Engineer" "Test Engineer" "Software Test"
    "SDET" "Automation Test" "Test Automation" "Quality Engineering"
    "Senior QA" "Senior Quality Engineer" "Senior SDET"
    "QA Lead" "Senior QA Lead" "Lead QA Engineer" "QA Manager" "Quality Assurance Manager"
    "Test Architect" "QA Architect" "Test Automation Architect" "Quality Engineering Architect"
    "Hardware QA" "Firmware Test" "Integration Test" "Embedded QA" "Systems QA"
    "AI QA" "ML Test Engineer" "Fintech QA" "Payments QA"
)

readonly VISA_SENIORITY_LEVELS=( "Senior" )
readonly VISA_FRIENDLY_COUNTRIES=( "AU" "DE" "GB" "CA" "IE" "NL" "SG" "AE" )

# ============================================================
# HELPER FUNCTIONS
# ============================================================
visa_log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_DIR/job_search_$(date +%Y%m%d).log"
}

visa_json_log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date -Iseconds)
    local version="${SCRIPT_VERSION:-unknown}"
    jq -cn \
        --arg ts "$timestamp" \
        --arg ver "$version" \
        --arg lvl "$level" \
        --arg msg "$message" \
        '{timestamp:$ts, version:$ver, level:$lvl, message:$msg}' \
        >> "$JSON_LOG_FILE" 2>/dev/null || true

    # Rotate JSON log atomically if it grows too large
    if [[ $(stat -c%s "$JSON_LOG_FILE" 2>/dev/null || echo 0) -gt 10485760 ]]; then
        local dir tmp_rotate
        dir=$(dirname "$JSON_LOG_FILE")
        if tmp_rotate=$(mktemp -p "$dir" .json_log.XXXXXX 2>/dev/null); then
            tail -n 5000 "$JSON_LOG_FILE" > "$tmp_rotate" 2>/dev/null
            mv "$tmp_rotate" "$JSON_LOG_FILE"
        else
            # Fallback: direct write (less atomic but better than nothing)
            tail -n 5000 "$JSON_LOG_FILE" > "$JSON_LOG_FILE.tmp" 2>/dev/null
            mv "$JSON_LOG_FILE.tmp" "$JSON_LOG_FILE"
        fi
    fi
}

visa_update_heartbeat() {
    # Atomic update: write to temp in the same directory, then move.
    # If the temp file creation fails, fall back to direct write.
    local dir tmp_heartbeat
    dir=$(dirname "$HEARTBEAT_FILE")
    if tmp_heartbeat=$(mktemp -p "$dir" .heartbeat.XXXXXX 2>/dev/null); then
        printf '%s:%s\n' "$(date +%s)" "$1" > "$tmp_heartbeat"
        mv "$tmp_heartbeat" "$HEARTBEAT_FILE"
    else
        printf '%s:%s\n' "$(date +%s)" "$1" > "$HEARTBEAT_FILE"
    fi
}

visa_job_is_seen() {
    grep -Fxq "$1" "$SEEN_FILE" 2>/dev/null
}

visa_mark_job_seen() {
    printf '%s\n' "$1" >> "$SEEN_FILE"
}

visa_rotate_seen_file() {
    if [[ $(date +%d) == "01" ]]; then
        local sentinel="$BIN_DIR/.seen_rotated_$(date +%Y%m)"
        if [[ ! -f "$sentinel" ]]; then
            if [[ -f "$SEEN_FILE" ]]; then
                tail -n 5000 "$SEEN_FILE" > "$SEEN_FILE.tmp"
                mv "$SEEN_FILE.tmp" "$SEEN_FILE"
                visa_json_log "INFO" "Rotated seen_jobs.txt"
                touch "$sentinel"
            fi
        fi
    else
        local current_month=$(date +%Y%m)
        for old in "$BIN_DIR"/.seen_rotated_*; do
            [[ -f "$old" && "$old" != "$BIN_DIR/.seen_rotated_$current_month" ]] && rm -f "$old"
        done
    fi

    find "$LOG_DIR" -name "job_search_*.log*" -type f -mtime +30 -delete 2>/dev/null || true

    local main_log="$LOG_DIR/job_search_$(date +%Y%m%d).log"
    if [[ -f "$main_log" ]]; then
        local size
        size=$(stat -c%s "$main_log" 2>/dev/null || echo 0)
        if [[ "$size" -gt 52428800 ]]; then
            mv "$main_log" "$main_log.$(date +%Y%m%d-%H%M%S)"
            visa_log "Rotated oversized main log (>50MB)"
        fi
    fi
}

# ============================================================
# API SEARCH
# ============================================================
visa_search_himalayas() {
    local keyword="$1"
    local seniority="$2"
    local results_file="$3"
    local -n output_count_ref="$4"
    local count=0
    
    if [[ ! "$seniority" =~ ^(Senior|Lead|Manager)$ ]]; then
        visa_log "⚠️ Skipping invalid seniority: $seniority (not supported by API)"
        output_count_ref=0
        return 0
    fi
    
    visa_log "🌄 Searching Himalayas: keyword='$keyword' seniority='$seniority'"
    
    local encoded_keyword
    encoded_keyword=$(jq -rn --arg kw "$keyword" '$kw | @uri')
    
    local url
    if $INCLUDE_WORLDWIDE; then
        url="https://himalayas.app/jobs/api/search?q=${encoded_keyword}&seniority=${seniority}&worldwide=true&employment_type=Full%20Time"
    else
        local location_params=""
        for country in "${VISA_FRIENDLY_COUNTRIES[@]}"; do
            if [[ -z "$location_params" ]]; then
                location_params="locationRestrictions[]=${country}"
            else
                location_params="${location_params}&locationRestrictions[]=${country}"
            fi
        done
        url="https://himalayas.app/jobs/api/search?q=${encoded_keyword}&seniority=${seniority}&${location_params}&employment_type=Full%20Time"
    fi
    
    # --- Create temp file for curl stderr ---
    local curl_err
    if ! curl_err=$(mktemp -p "${TMPDIR:-/tmp}"); then
        visa_log "   ⚠️ mktemp failed for curl_err"
        output_count_ref=0
        return 1
    fi
    
    local response
    local curl_rc
    # Use if/else to capture exit code without changing global shell options
    if response=$(curl -fsS \
        --connect-timeout 10 \
        --max-time 30 \
        "${CURL_RETRY_ARGS[@]}" \
        "$url" 2>"$curl_err"); then
        curl_rc=0
    else
        curl_rc=$?
    fi
    
    if (( curl_rc != 0 )); then
        local err_msg
        err_msg=$(<"$curl_err")
        visa_log "   ⚠️ curl failed (exit $curl_rc): ${err_msg:-no error message}"
        rm -f "$curl_err"
        output_count_ref=0
        return 0
    fi
    rm -f "$curl_err"   # curl_err is no longer needed
    
    # --- Validate JSON and ensure .jobs is an array ---
    if ! jq -e '.jobs | arrays' <<<"$response" >/dev/null 2>&1; then
        visa_log "   ⚠️ Invalid response: missing .jobs array"
        output_count_ref=0
        return 0
    fi
    
    local job_count
    job_count=$(jq -r '.jobs | length' <<<"$response" 2>/dev/null || echo 0)
    if (( job_count == 0 )); then
        visa_log "   No jobs found in response"
        output_count_ref=0
        return 0
    fi
    
    # --- Create temp file for jq extraction ---
    local jq_temp
    if ! jq_temp=$(mktemp -p "${TMPDIR:-/tmp}"); then
        visa_log "   ⚠️ mktemp failed for jq_temp"
        output_count_ref=0
        return 1
    fi
    
    # --- Extract jobs; on failure, clean up and return ---
    if ! jq -r '.jobs[]? | 
        .title as $title | 
        .companyName as $company | 
        ((.locationRestrictions // ["Worldwide"])[0]) as $location | 
        .applicationLink as $url | 
        (.minSalary // "") as $salary_min | 
        (.maxSalary // "") as $salary_max | 
        (.currency // "") as $salary_currency | 
        "\($title)|\($company)|\($location)|\($url)|\($salary_min)|\($salary_max)|\($salary_currency)"' <<<"$response" > "$jq_temp" 2>/dev/null
    then
        visa_log "   ⚠️ jq extraction failed"
        rm -f "$jq_temp"
        output_count_ref=0
        return 0
    fi
    
    # --- Process extracted jobs ---
    while IFS='|' read -r title company location url salary_min salary_max salary_currency; do
        if [[ -z "$title" ]] || [[ -z "$company" ]]; then
            continue
        fi
        
        # Use md5sum for fast deterministic identifiers (not cryptographic)
        local job_hash
        job_hash=$(printf '%s' "$url" | md5sum)
        job_hash="${job_hash%% *}"
        local job_id="him-${job_hash:0:10}"
        
        if ! visa_job_is_seen "$job_id"; then
            local salary_text=""
            if [[ -n "$salary_min" && "$salary_min" != "null" && "$salary_min" != "" ]]; then
                salary_text=" (${salary_currency}${salary_min}-${salary_max})"
            fi
            
            printf '%s\n' "HIMALAYAS|$seniority|$title|$company|$location|$url|$salary_text" >> "$results_file"
            visa_mark_job_seen "$job_id"
            count=$((count + 1))
        fi
    done < "$jq_temp"
    
    rm -f "$jq_temp"
    
    visa_log "   ✓ Found $count new jobs"
    
    output_count_ref=$count
}

# ============================================================
# EMAIL FUNCTION
# ============================================================
visa_send_email() {
    local results_file="$1"
    local total_count="$2"
    local rc=0
    
    if (( total_count == 0 )); then
        visa_log "No new jobs found, skipping email"
        return 0
    fi
    
    local subject="🎯 Visa Sponsorships Job Alert: $total_count new QA/SDET positions (semantic search)"
    
    local email_body
    if ! email_body=$(mktemp -p "${TMPDIR:-/tmp}"); then
        visa_log "Failed to create email temp file"
        return 1
    fi
    
    # Build email header (using printf for structured data)
    {
        printf 'To: %s\n' "$EMAIL_TO"
        printf 'Subject: %s\n' "$subject"
        printf 'Content-Type: text/plain; charset=UTF-8\n'
        printf '\n'
        printf 'Hi Claive,\n'
        printf '\n'
        printf '🌍 Found %d new QA/SDET opportunities using semantic keyword search:\n' "$total_count"
        printf '\n'
        printf '============================================================\n'
        printf 'SEARCH METHOD:\n'
        printf '  Keywords: %s\n' "${QA_KEYWORDS[*]}"
        printf '  Seniorities: %s\n' "${VISA_SENIORITY_LEVELS[*]}"
        if ! $INCLUDE_WORLDWIDE; then
            printf '  Location: Visa-friendly countries only (%s)\n' "${VISA_FRIENDLY_COUNTRIES[*]}"
        else
            printf '  Location: Worldwide\n'
        fi
        printf '============================================================\n'
        printf '\n'
    } > "$email_body"

    # List jobs using process substitution – no temporary file needed
    {
        local first=1
        while IFS='|' read -r source seniority title company location url salary; do
            if (( first )); then
                printf '📌 NEW JOB POSTINGS:\n'
                printf '\n'
                first=0
            fi
            
            local salary_display=""
            if [[ -n "$salary" && "$salary" != "null" ]]; then
                salary_display=" - $salary"
            fi
            
            printf '📍 %s @ %s (%s)%s\n' "$title" "$company" "$location" "$salary_display"
            printf '   🔗 %s\n' "$url"
            printf '   🎓 Seniority: %s\n' "$seniority"
            printf '\n'
        done < <(grep '^HIMALAYAS|' "$results_file" 2>/dev/null)
    } >> "$email_body"

    # Summary
    {
        printf '\n---\n'
        printf '📊 SUMMARY\n'
        printf '   Total new jobs: %d\n' "$total_count"
        printf '\n'
        printf '📅 Search performed on: %s\n' "$(date)"
        printf '\n'
        printf '💡 Apply quickly – positions may close soon.\n'
        printf '\n'
        printf '---\n'
        printf '🔧 To modify search keywords or seniority levels, edit the script.\n'
    } >> "$email_body"

    if ! msmtp -a default "$EMAIL_TO" < "$email_body"; then
        visa_log "Failed to send email"
        rc=1
    else
        visa_log "Email sent with $total_count jobs (semantic mode)"
    fi
    
    rm -f "$email_body"
    return "$rc"
}

# ============================================================
# MAIN SEARCH CYCLE
# ============================================================
visa_main_cycle() {
    visa_rotate_seen_file
    visa_json_log "INFO" "Starting semantic job search cycle"
    
    visa_log "=========================================="
    visa_log "Semantic Job Search Started"
    visa_log "Keywords: ${QA_KEYWORDS[*]}"
    visa_log "Seniorities: ${VISA_SENIORITY_LEVELS[*]}"
    visa_log "=========================================="
    
    local temp_results
    if ! temp_results=$(mktemp -p "${TMPDIR:-/tmp}"); then
        visa_log "FATAL: Could not create temp results file"
        return 1
    fi
    
    local total_found=0
    
    for keyword in "${QA_KEYWORDS[@]}"; do
        for seniority in "${VISA_SENIORITY_LEVELS[@]}"; do
            local run_count=0
            visa_search_himalayas "$keyword" "$seniority" "$temp_results" run_count
            total_found=$((total_found + run_count))
        done
    done
    
    visa_log "=========================================="
    visa_log "Search Complete - Found $total_found new jobs"
    visa_log "=========================================="
    
    if (( total_found > 0 )); then
        visa_send_email "$temp_results" "$total_found"
        echo ""
        echo "📊 JOB SEARCH SUMMARY:"
        echo "   Total new jobs: $total_found"
        echo ""
        visa_json_log "SUCCESS" "Sent email with $total_found jobs (semantic search)"
    else
        visa_json_log "INFO" "No new jobs found"
    fi
    
    cat "$temp_results" >> "$LOG_DIR/job_search_$(date +%Y%m%d).log" 2>/dev/null || true
    
    # Explicit cleanup
    rm -f "$temp_results"
    
    visa_update_heartbeat "$total_found"
    visa_json_log "INFO" "Cycle complete"
    
    visa_log "Search complete!"
}

# ============================================================
# EXECUTION FLOW
# ============================================================
if $RUN_ONCE; then
    visa_log "Executing single test pass (--once matched)..."
    visa_main_cycle
    exit 0
fi

while true; do
    visa_main_cycle
    
    MINS=$(( (RANDOM % 21) + 55 ))
    echo "$(date): Cycle complete. Sleeping for $MINS minutes..." | tee -a "$LOG_DIR/job_search_$(date +%Y%m%d).log"
    visa_json_log "INFO" "Sleeping for $MINS minutes (jittered 55-75 min)"
    sleep "${MINS}m"
done
