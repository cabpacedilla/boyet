#!/usr/bin/env bash

#~ LOCK_FILE="/tmp/job_rotate_$(whoami).lock"
#~ exec 9>"${LOCK_FILE}"
#~ if ! flock -n 9; then
    #~ exit 1
#~ fi

#~ # Store our PID
#~ echo $$ > "$LOCK_FILE"

#~ # Enhanced cleanup that only removes our PID file
#~ cleanup() {
    #~ # Only remove if it's our PID (prevents removing another process's lock)
    #~ if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        #~ rm -f "$LOCK_FILE"
    #~ fi
    #~ flock -u 9
    #~ exec 9>&-
#~ }

#~ trap cleanup EXIT

# --- CONFIGURATION ---
BIN_DIR="$HOME/Documents/bin"
SEEN_FILE="$BIN_DIR/seen_jobs.txt"
LOG_FILE="$BIN_DIR/job_search.log"
ALERT_EMAIL="cabpacedilla@gmail.com"

mkdir -p "$BIN_DIR"
touch "$SEEN_FILE"

# Monthly Maintenance - Fixed: Use quotes and proper comparison
[[ $(date +%d) == "01" ]] && > "$SEEN_FILE"

echo "Job Search Engine Active. Mode: Acedilla-Resume Optimization."

while true; do
    echo "------------------------------------------------" >> "$LOG_FILE"
    echo "$(date): Starting Search Cycle (LinkedIn, Indeed, JobStreet, Mynimo)..." >> "$LOG_FILE"

    # Calculate day of year (remove leading zeros to avoid octal issues)
	DAY_OF_YEAR=$(date +%j | sed 's/^0*//')
	QUERY_INDEX=$((DAY_OF_YEAR % 6))

	case $QUERY_INDEX in
		0)
			# Strategy 0: SDET / Modern Automation (Cypress + Python) - CONTRACT/REMOTE ONLY
			SELECTED_QUERY="(\"Senior QA\" OR SDET OR \"Automation Engineer\" OR \"Test Automation\") AND (Python OR Cypress OR Selenium OR Postman OR API) AND (Contract OR Remote OR Part-time OR Freelance) NOT (\"Full-time\" OR Permanent)"
			STRATEGY="SDET / Automation Specialist - CONTRACT/REMOTE ONLY"
			;;
		1)
			# Strategy 1: QAOps / Linux Infrastructure - CONTRACT/REMOTE ONLY
			SELECTED_QUERY="(\"Senior QA\" OR \"Quality Engineer\" OR \"Test Engineer\" OR \"Software Test\") AND (Bash OR Shell OR Linux OR DevOps OR CI/CD) AND (Contract OR Remote OR Part-time OR Freelance) NOT (\"Full-time\" OR Permanent)"
			STRATEGY="QAOps / Linux Infrastructure - CONTRACT/REMOTE ONLY"
			;;
		2)
			# Strategy 2: Domain Expert (Payroll, POS, Salesforce, E-commerce) - CONTRACT/REMOTE ONLY
			SELECTED_QUERY="(\"Senior QA\" OR \"Quality Assurance\" OR \"Software Tester\") AND (Payroll OR POS OR Salesforce OR \"E-commerce\" OR ERP) AND (Contract OR Remote OR Part-time OR Freelance) NOT (\"Full-time\" OR Permanent)"
			STRATEGY="Domain Expert (Payroll/POS/Salesforce) - CONTRACT/REMOTE ONLY"
			;;
		3)
			# Strategy 3: Leadership & Management (Lead, Manager, Architect) - CONTRACT/REMOTE ONLY
			SELECTED_QUERY="(\"QA Lead\" OR \"Senior QA Lead\" OR \"Lead QA Engineer\" OR \"QA Manager\" OR \"Quality Assurance Manager\" OR \"Test Architect\" OR \"QA Architect\" OR \"Test Automation Architect\" OR \"Quality Engineering Architect\") AND (Contract OR Remote OR Part-time OR Freelance) NOT (\"Full-time\" OR Permanent)"
			STRATEGY="Leadership / Management / Architect - CONTRACT/REMOTE ONLY"
			;;
		4)
			# Strategy 4: Specialized Hardware / Firmware / Embedded / Systems - CONTRACT/REMOTE ONLY
			SELECTED_QUERY="(\"Hardware QA\" OR \"Firmware Test\" OR \"Integration Test\" OR \"Embedded QA\" OR \"Systems QA\" OR \"Hardware Test\") AND (Contract OR Remote OR Part-time OR Freelance) NOT (\"Full-time\" OR Permanent)"
			STRATEGY="Hardware / Firmware / Embedded QA - CONTRACT/REMOTE ONLY"
			;;
		5)
			# Strategy 5: Emerging Technologies (AI, ML, Fintech, Payments) - CONTRACT/REMOTE ONLY
			SELECTED_QUERY="(\"AI QA\" OR \"ML Test Engineer\" OR \"Fintech QA\" OR \"Payments QA\" OR \"Machine Learning Test\") AND (Contract OR Remote OR Part-time OR Freelance) NOT (\"Full-time\" OR Permanent)"
			STRATEGY="AI / ML / Fintech / Payments QA - CONTRACT/REMOTE ONLY"
			;;
	esac

    echo "$(date): Strategy: $STRATEGY" >> "$LOG_FILE"
    echo "$(date): Running Scraper for: $SELECTED_QUERY" >> "$LOG_FILE"

    # Execution (5-minute timeout for 4 portals + human-delays)
    RAW_RESULTS=$(timeout 300s python3 "$BIN_DIR/find_jobs.py" "$SELECTED_QUERY")
    
    NEW_JOBS_BODY=""
    COUNT=0

    while read -r line; do
        [[ -z "$line" || "$line" == DEBUG* ]] && continue
        
        ID=$(echo "$line" | cut -d'|' -f1)
        TITLE=$(echo "$line" | cut -d'|' -f2)
        COMPANY=$(echo "$line" | cut -d'|' -f3)
        LINK=$(echo "$line" | cut -d'|' -f4)

        if ! grep -q "$ID" "$SEEN_FILE"; then
            NEW_JOBS_BODY+=$'📍 '"$TITLE"$' @ '"$COMPANY"$'\n🔗 '"$LINK"$'\n\n'
            echo "$ID" >> "$SEEN_FILE"
            ((COUNT++))
        fi
    done <<< "$RAW_RESULTS"

    if [[ -n "$NEW_JOBS_BODY" ]]; then
        SUBJECT="[$COUNT New Contract/Remote Jobs] $STRATEGY"
        {
            echo "To: $ALERT_EMAIL"
            echo "Subject: $SUBJECT"
            echo "Content-Type: text/plain; charset=UTF-8"
            echo ""
            echo -e "Hi Claive,\n\nI found $COUNT potential contract/remote/freelance matches:\n\n$STRATEGY\n\n$NEW_JOBS_BODY\n---\nSearch Query: $SELECTED_QUERY"
        } | msmtp -a default "$ALERT_EMAIL"
        echo "$(date): SUCCESS - Sent email for $COUNT jobs." >> "$LOG_FILE"
    else
        echo "$(date): INFO - No new contract/remote matches found." >> "$LOG_FILE"
    fi

    # Jittered sleep (55-75 minutes)
    MINS=$(( (RANDOM % 21) + 55 ))
    echo "$(date): Sleeping for $MINS minutes..." >> "$LOG_FILE"
    sleep "${MINS}m"
done
