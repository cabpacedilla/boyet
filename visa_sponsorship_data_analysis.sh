#!/usr/bin/env bash
# ============================================================
# Himalayas Job Search - Senior Data Analysis Roles
# Runs continuously with jittered intervals (~22 times/day)
# ============================================================

set -uo pipefail

# --- CONFIGURATION ---
readonly BIN_DIR="$HOME/Documents/bin"
readonly SEEN_FILE="$BIN_DIR/jobs_seen.txt"
readonly LOG_DIR="$HOME/scriptlogs/job_search"
readonly JSON_LOG_FILE="$BIN_DIR/visa_job_search.jsonl"  
readonly HEARTBEAT_FILE="$BIN_DIR/visa_job_engine.heartbeat"
readonly EMAIL_TO="claive21@hotmail.com"

# IMPORTANT: Set to true for worldwide search, false for visa-friendly countries only
readonly INCLUDE_WORLDWIDE=true

mkdir -p "$LOG_DIR" "$BIN_DIR"
touch "$SEEN_FILE" "$JSON_LOG_FILE"


# ============================================================
# JOB TITLES
# ============================================================
readonly VISA_JOB_TITLES=(
    "Senior Data Analyst"
    "Lead Data Analyst"
    "Principal Data Analyst"
    "Data Analytics Manager"
    "Senior Business Intelligence Analyst"
    "Lead Business Intelligence Analyst"
    "BI Manager"
    "Analytics Manager"
    "Senior Insights Analyst"
    "Lead Insights Analyst"
    "Data Analysis Team Lead"
    "Director of Data Analysis"
    "Senior Data Scientist"          # if role focuses on analysis/insights
    "Lead Data Scientist"            # with emphasis on analytics
    "Senior Reporting Analyst"
    "Lead Reporting Analyst"
    "Data Governance Analyst Senior"
    "Senior Product Analyst"
    "Lead Product Analyst"
    "Analytics Architect"
    "Data Strategy Analyst Senior"
)

# ============================================================
# SENIORITY LEVELS
# ============================================================
readonly VISA_SENIORITY_LEVELS=(
    "Senior"
    "Lead"
    "Manager"
    "Staff"
    "Principal"
)

# ============================================================
# VISA-FRIENDLY COUNTRIES
# ============================================================
readonly VISA_FRIENDLY_COUNTRIES=(
    "AU"  # Australia (482, 186 visas)
    "DE"  # Germany (Blue Card)
    "GB"  # United Kingdom (Skilled Worker)
    "CA"  # Canada (Global Talent Stream)
    "IE"  # Ireland (Critical Skills)
    "NL"  # Netherlands (Highly Skilled Migrant)
    "SG"  # Singapore (Employment Pass)
    "AE"  # UAE (Golden Visa)
)

# ============================================================
# HELPER FUNCTIONS
# ============================================================
visa_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_DIR/job_search_$(date +%Y%m%d).log"
}

visa_json_log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date -Iseconds)
    echo "{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"message\":\"$message\"}" >> "$JSON_LOG_FILE"
    # Rotate JSON log if it grows beyond 10 MB
    if [[ $(stat -c%s "$JSON_LOG_FILE" 2>/dev/null) -gt 10485760 ]]; then
        tail -n 5000 "$JSON_LOG_FILE" > "$JSON_LOG_FILE.tmp"
        mv "$JSON_LOG_FILE.tmp" "$JSON_LOG_FILE"
    fi
}

visa_update_heartbeat() {
    local count="$1"
    echo "$(date +%s):$count" > "$HEARTBEAT_FILE"
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
# HIMALAYAS API SEARCH (NO PIPELINES, NO PROCESS SUBSTITUTION)
# ============================================================
visa_search_himalayas() {
    local keyword="$1"
    local seniority="$2"
    local results_file="$3"
    local count=0
    
    visa_log "🌄 Searching Himalayas API: $keyword ($seniority)"
    
    local encoded_keyword=$(echo "$keyword" | sed 's/ /%20/g')
    
    local url
    if [[ "$INCLUDE_WORLDWIDE" == "true" ]]; then
        url="https://himalayas.app/jobs/api/search?q=${encoded_keyword}&seniority=${seniority}&worldwide=true&employment_type=Full%20Time"
        visa_log "   Location: Worldwide"
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
        visa_log "   Location: Visa-friendly countries only"
    fi
    
    local response=$(curl -s --max-time 30 "$url" 2>/dev/null)
    
    if [[ -z "$response" ]] || [[ "$response" == "[]" ]]; then
        visa_log "   No results from Himalayas"
        return 0
    fi
    
    # Write jq output to a temporary file (no pipeline in the while loop)
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
    
    # Read from the temporary file – no subshell
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
            
            echo "HIMALAYAS|$seniority|$title|$company|$location|$url|Remote$salary_text" >> "$results_file"
            visa_mark_job_seen "$job_id"
            ((count++))
        fi
    done < "$jq_temp"
    
    rm -f "$jq_temp"
    visa_log "   ✓ Found $count new jobs from Himalayas"
}

# ============================================================
# EMAIL FUNCTION (NO PIPELINES, NO PROCESS SUBSTITUTION)
# ============================================================
visa_send_email() {
    local results_file="$1"
    local total_count="$2"
    
    if [[ $total_count -eq 0 ]]; then
        visa_log "No new jobs found, skipping email"
        return 0
    fi
    
    local subject="🎯 Visa Sponsorships Job Alert: $total_count new Senior Data Analysis positions"
    
    {
        echo "To: $EMAIL_TO"
        echo "Subject: $subject"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo ""
        echo "Hi Claive,"
        echo ""
        echo "🌍 Found $total_count new senior QA/SDET opportunities:"
        echo ""
        echo "============================================================"
        echo "LEGEND:"
        echo "  🌍 Remote roles (always available)"
        if [[ "$INCLUDE_WORLDWIDE" == "false" ]]; then
            echo ""
            echo "📍 LOCATION FILTER: Visa-friendly countries only"
            echo "   Countries: ${VISA_FRIENDLY_COUNTRIES[*]}"
        fi
        echo "============================================================"
        echo ""
    } > /tmp/visa_email_body.txt

    # Use a temporary file for filtering (no pipeline)
    local grep_temp=$(mktemp)
    grep "^HIMALAYAS" "$results_file" > "$grep_temp" 2>/dev/null
    
    if [[ -s "$grep_temp" ]]; then
        echo "🌍 REMOTE ROLES:" >> /tmp/visa_email_body.txt
        echo "" >> /tmp/visa_email_body.txt
        
        while IFS='|' read -r source seniority title company location url salary; do
            local clean_company="$company"
            local salary_display=""
            if [[ "$salary" != "Remote" && "$salary" != "null" && -n "$salary" ]]; then
                salary_display=" - $salary"
            fi
            
            echo "📍 $title @ $clean_company$salary_display" >> /tmp/visa_email_body.txt
            echo "   🔗 $url" >> /tmp/visa_email_body.txt
            echo "" >> /tmp/visa_email_body.txt
        done < "$grep_temp"
    fi
    rm -f "$grep_temp"

    {
        echo "---"
        echo "📊 SUMMARY"
        echo "   Total jobs found: $total_count"
        echo ""
        echo "🔍 SEARCH CRITERIA"
        echo "   Seniority levels: ${VISA_SENIORITY_LEVELS[*]}"
        echo "   Job titles: ${VISA_JOB_TITLES[*]}"
        echo ""
        echo "📅 Search performed on: $(date)"
        echo ""
        echo "💡 Apply quickly! These positions may close soon."
        echo ""
        echo "---"
        echo "🔧 To modify search parameters, edit the script configuration."
    } >> /tmp/visa_email_body.txt

    msmtp -a default "$EMAIL_TO" < /tmp/visa_email_body.txt 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        visa_log "Email sent with $total_count jobs (clean format)"
    else
        visa_log "Failed to send email"
    fi
    
    rm -f /tmp/visa_email_body.txt
}

# ============================================================
# MAIN SEARCH CYCLE
# ============================================================
visa_main_cycle() {
    visa_rotate_seen_file
    visa_json_log "INFO" "Starting visa sponsorship search cycle"
    
    visa_log "=========================================="
    visa_log "Himalayas Job Search Started"
    visa_log "=========================================="
    
    local temp_results=$(mktemp)
    local VISA_COUNT=0
    
    for title in "${VISA_JOB_TITLES[@]}"; do
        for seniority in "${VISA_SENIORITY_LEVELS[@]}"; do
            visa_search_himalayas "$title" "$seniority" "$temp_results"
        done
    done
    
    local total_count
    total_count=$(grep -c "^HIMALAYAS" "$temp_results" 2>/dev/null || echo "0")
    VISA_COUNT=$total_count
    
    visa_log "=========================================="
    visa_log "Search Complete - Found $total_count new jobs"
    visa_log "=========================================="
    
    if [[ "$total_count" -gt 0 ]]; then
        visa_send_email "$temp_results" "$total_count"
        
        echo ""
        echo "📊 JOB SEARCH SUMMARY:"
        echo "   Himalayas: $total_count"
        echo ""
        
        visa_json_log "SUCCESS" "Sent email with $total_count visa sponsorship jobs"
    else
        visa_json_log "INFO" "No new jobs found"
    fi
    
    cat "$temp_results" >> "$LOG_DIR/job_search_$(date +%Y%m%d).log" 2>/dev/null
    rm -f "$temp_results"
    
    visa_update_heartbeat "$VISA_COUNT"
    visa_json_log "INFO" "Cycle complete"
    
    visa_log "Search complete!"
}

# ============================================================
# INFINITE LOOP WITH JITTER (~22 runs per day)
# ============================================================
while true; do
    visa_main_cycle
    
    MINS=$(( (RANDOM % 21) + 55 ))
    echo "$(date): Cycle complete. Sleeping for $MINS minutes..." | tee -a "$LOG_DIR/job_search_$(date +%Y%m%d).log"
    visa_json_log "INFO" "Sleeping for $MINS minutes (jittered 55-75 min)"
    sleep "${MINS}m"
done
