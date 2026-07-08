#!/usr/bin/env bash
# ============================================================
# Himalayas Job Search - Senior QA/SDET Roles (Semantic Mode)
# Keyword-based search for maximum coverage with minimal API calls
# VERSION: 2.1 - Fixed grep newline bug and invalid seniorities
# ============================================================

set -Euo pipefail

# --- CONFIGURATION ---
readonly BIN_DIR="$HOME/Documents/bin"
readonly SEEN_FILE="$BIN_DIR/jobs_seen.txt"
readonly LOG_DIR="$HOME/scriptlogs/job_search"
readonly JSON_LOG_FILE="$BIN_DIR/visa_job_search.jsonl"  
readonly HEARTBEAT_FILE="$BIN_DIR/visa_job_engine.heartbeat"
readonly EMAIL_TO="cabpacedilla@gmail.com"

# IMPORTANT: Set to true for worldwide search, false for visa-friendly countries only
readonly INCLUDE_WORLDWIDE=true

mkdir -p "$LOG_DIR" "$BIN_DIR"
touch "$SEEN_FILE" "$JSON_LOG_FILE"

# --- LOCKING ---
#~ readonly LOCK_FILE="/tmp/visa_job_scraper_$(whoami).lock"
#~ exec 9>"$LOCK_FILE"

#~ if ! flock -n 9; then
    #~ echo "$(date): Another instance running, exiting." >&2
    #~ exit 1
#~ fi

#~ echo $$ > "$LOCK_FILE"

#~ cleanup() {
    #~ pkill -P $$ 2>/dev/null
    #~ if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        #~ rm -f "$LOCK_FILE"
    #~ fi
    #~ flock -u 9 2>/dev/null || true
    #~ exec 9>&- 2>/dev/null || true
#~ }

#~ trap '
    #~ visa_json_log "WARN" "SIGTERM received"
    #~ cleanup
    #~ exit 143
#~ ' TERM

#~ trap '
    #~ visa_json_log "WARN" "SIGINT received"
    #~ cleanup
    #~ exit 130
#~ ' INT

#~ trap '
    #~ rc=$?
    #~ if (( rc != 0 )); then
        #~ visa_json_log "ERROR" "Unexpected exit rc=$rc line=$LINENO"
    #~ else
        #~ visa_json_log "INFO" "Normal exit"
    #~ fi
    #~ cleanup
#~ ' EXIT

#~ trap '
    #~ rc=$?
    #~ visa_json_log "ERROR" "ERR trap rc=$rc line=$LINENO command=${BASH_COMMAND}"
#~ ' ERR

# ============================================================
# SEMANTIC KEYWORDS (instead of fixed job titles)
# These are broad, high-recall terms that capture real-world variations
# ============================================================
readonly QA_KEYWORDS=(
    "QA"
    "Quality Assurance"
    "Test Engineer"
    "Software Test"
    "SDET"
    "Automation Test"
    "Quality Engineering"
    "Senior QA Lead"          
    "Principal QA"            
    "QA Manager"              
    "Test Automation Architect" 
    "Data Encoder"
)

# ============================================================
# SENIORITY LEVELS - UPDATED to only API-supported values
# API only accepts: Senior, Lead, Manager
# Staff, Principal, Junior removed (caused API errors)
# ============================================================
readonly VISA_SENIORITY_LEVELS=(
    "Senior"
    "Lead"
    "Manager"
)

# ============================================================
# VISA-FRIENDLY COUNTRIES (unchanged)
# ============================================================
readonly VISA_FRIENDLY_COUNTRIES=(
    "AU" "DE" "GB" "CA" "IE" "NL" "SG" "AE"
)

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
    local timestamp=$(date -Iseconds)
    echo "{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"message\":\"$message\"}" >> "$JSON_LOG_FILE" 2>/dev/null || true
    if [[ $(stat -c%s "$JSON_LOG_FILE" 2>/dev/null) -gt 10485760 ]]; then
        tail -n 5000 "$JSON_LOG_FILE" > "$JSON_LOG_FILE.tmp"
        mv "$JSON_LOG_FILE.tmp" "$JSON_LOG_FILE"
    fi
}

# FIXED: Heartbeat function now strips newlines
visa_update_heartbeat() {
    local count="$1"
    local clean_count=$(echo "$count" | tr -d '\n\r' | xargs)
    echo "$(date +%s):$clean_count" > "$HEARTBEAT_FILE"
}

visa_job_is_seen() {
    grep -Fxq "$1" "$SEEN_FILE" 2>/dev/null
}

visa_mark_job_seen() {
    echo "$1" >> "$SEEN_FILE"
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
}

# ============================================================
# HIMALAYAS API SEARCH (Keyword + Seniority)
# ============================================================
visa_search_himalayas() {
    local keyword="$1"
    local seniority="$2"
    local results_file="$3"
    local count=0  # Initialize properly
    
    # Skip invalid seniority values
    if [[ ! "$seniority" =~ ^(Senior|Lead|Manager)$ ]]; then
        visa_log "⚠️ Skipping invalid seniority: $seniority (not supported by API)"
        return 0
    fi
    
    visa_log "🌄 Searching Himalayas: keyword='$keyword' seniority='$seniority'"
    
    local encoded_keyword=$(echo "$keyword" | sed 's/ /%20/g')
    
    local url
    if [[ "$INCLUDE_WORLDWIDE" == "true" ]]; then
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
    
    local response=$(curl -s --max-time 30 "$url" 2>/dev/null)
    
    if [[ -z "$response" ]] || [[ "$response" == "[]" ]]; then
        visa_log "   No results"
        return 0
    fi
    
    local jq_temp=$(mktemp)
    echo "$response" | timeout 10s jq -r '.jobs[]? | 
        .title as $title |
        .companyName as $company |
        ((.locationRestrictions // ["Worldwide"])[0]) as $location |
        .applicationLink as $url |
        (.minSalary // "") as $salary_min |
        (.maxSalary // "") as $salary_max |
        (.currency // "") as $salary_currency |
        "\($title)|\($company)|\($location)|\($url)|\($salary_min)|\($salary_max)|\($salary_currency)"' 2>/dev/null > "$jq_temp"
    
    while IFS='|' read -r title company location url salary_min salary_max salary_currency; do
        if [[ -z "$title" ]] || [[ -z "$company" ]]; then
            continue
        fi
        
        local job_id="him-$(echo "$url" | md5sum | cut -c1-10)"
        
        if ! visa_job_is_seen "$job_id"; then
            local salary_text=""
            if [[ -n "$salary_min" && "$salary_min" != "null" && "$salary_min" != "" ]]; then
                salary_text=" (${salary_currency}${salary_min}-${salary_max})"
            fi
            
            echo "HIMALAYAS|$seniority|$title|$company|$location|$url|$salary_text" >> "$results_file"
            visa_mark_job_seen "$job_id"
            count=$((count + 1))
        fi
    done < "$jq_temp"
    
    rm -f "$jq_temp"
    visa_log "   ✓ Found $count new jobs"
}

# ============================================================
# EMAIL FUNCTION
# ============================================================
visa_send_email() {
    local results_file="$1"
    local total_count="$2"
    
    if [[ $total_count -eq 0 ]]; then
        visa_log "No new jobs found, skipping email"
        return 0
    fi
    
    local subject="🎯 Visa Sponsorships Job Alert: $total_count new QA/SDET positions (semantic search)"
    
    {
        echo "To: $EMAIL_TO"
        echo "Subject: $subject"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo ""
        echo "Hi Claive,"
        echo ""
        echo "🌍 Found $total_count new QA/SDET opportunities using semantic keyword search:"
        echo ""
        echo "============================================================"
        echo "SEARCH METHOD:"
        echo "  Keywords: ${QA_KEYWORDS[*]}"
        echo "  Seniorities: ${VISA_SENIORITY_LEVELS[*]}"
        if [[ "$INCLUDE_WORLDWIDE" == "false" ]]; then
            echo "  Location: Visa-friendly countries only (${VISA_FRIENDLY_COUNTRIES[*]})"
        else
            echo "  Location: Worldwide"
        fi
        echo "============================================================"
        echo ""
    } > /tmp/visa_email_body.txt

    local grep_temp=$(mktemp)
    grep "^HIMALAYAS" "$results_file" > "$grep_temp" 2>/dev/null
    
    if [[ -s "$grep_temp" ]]; then
        echo "📌 NEW JOB POSTINGS:" >> /tmp/visa_email_body.txt
        echo "" >> /tmp/visa_email_body.txt
        
        while IFS='|' read -r source seniority title company location url salary; do
            local salary_display=""
            if [[ -n "$salary" && "$salary" != "null" ]]; then
                salary_display=" - $salary"
            fi
            
            echo "📍 $title @ $company ($location)$salary_display" >> /tmp/visa_email_body.txt
            echo "   🔗 $url" >> /tmp/visa_email_body.txt
            echo "   🎓 Seniority: $seniority" >> /tmp/visa_email_body.txt
            echo "" >> /tmp/visa_email_body.txt
        done < "$grep_temp"
    fi
    rm -f "$grep_temp"

    {
        echo "---"
        echo "📊 SUMMARY"
        echo "   Total new jobs: $total_count"
        echo ""
        echo "📅 Search performed on: $(date)"
        echo ""
        echo "💡 Apply quickly – positions may close soon."
        echo ""
        echo "---"
        echo "🔧 To modify search keywords or seniority levels, edit the script."
    } >> /tmp/visa_email_body.txt

    msmtp -a default "$EMAIL_TO" < /tmp/visa_email_body.txt 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        visa_log "Email sent with $total_count jobs (semantic mode)"
    else
        visa_log "Failed to send email"
    fi
    
    rm -f /tmp/visa_email_body.txt
}

# ============================================================
# MAIN SEARCH CYCLE (Keyword × Seniority)
# ============================================================
visa_main_cycle() {
    visa_rotate_seen_file
    visa_json_log "INFO" "Starting semantic job search cycle"
    
    visa_log "=========================================="
    visa_log "Semantic Job Search Started"
    visa_log "Keywords: ${QA_KEYWORDS[*]}"
    visa_log "Seniorities: ${VISA_SENIORITY_LEVELS[*]}"
    visa_log "=========================================="
    
    local temp_results=$(mktemp)
    local total_found=0
    
    for keyword in "${QA_KEYWORDS[@]}"; do
        for seniority in "${VISA_SENIORITY_LEVELS[@]}"; do
            visa_search_himalayas "$keyword" "$seniority" "$temp_results"
        done
    done
    
    # FIXED: grep -c can add newlines, so we clean the output
    # Using awk instead for cleaner number handling
    total_found=$(awk '/^HIMALAYAS/ {count++} END {print count+0}' "$temp_results")
    
    visa_log "=========================================="
    visa_log "Search Complete - Found $total_found new jobs"
    visa_log "=========================================="
    
    if [[ "$total_found" -gt 0 ]]; then
        visa_send_email "$temp_results" "$total_found"
        echo ""
        echo "📊 JOB SEARCH SUMMARY:"
        echo "   Total new jobs: $total_found"
        echo ""
        visa_json_log "SUCCESS" "Sent email with $total_found jobs (semantic search)"
    else
        visa_json_log "INFO" "No new jobs found"
    fi
    
    cat "$temp_results" >> "$LOG_DIR/job_search_$(date +%Y%m%d).log" 2>/dev/null
    rm -f "$temp_results"
    
    visa_update_heartbeat "$total_found"
    visa_json_log "INFO" "Cycle complete"
    
    visa_log "Search complete!"
}

# ============================================================
# INFINITE LOOP WITH JITTER (~22 runs/day)
# ============================================================
while true; do
    visa_main_cycle
    
    MINS=$(( (RANDOM % 21) + 55 ))
    echo "$(date): Cycle complete. Sleeping for $MINS minutes..." | tee -a "$LOG_DIR/job_search_$(date +%Y%m%d).log"
    visa_json_log "INFO" "Sleeping for $MINS minutes (jittered 55-75 min)"
    sleep "${MINS}m"
done
