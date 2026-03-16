#!/bin/bash

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

    # Fixed: Remove leading zero to prevent octal interpretation
    DAY_OF_YEAR=$(date +%j | sed 's/^0*//')
    QUERY_INDEX=$((DAY_OF_YEAR % 3))

    case $QUERY_INDEX in
        0)
            # Focus: SDET / Modern Automation (Cypress + Python) - EXCLUDE FULL-TIME
            SELECTED_QUERY="(\"Senior QA\" OR SDET) AND (Python OR Cypress) AND (Selenium OR Postman OR API) AND (Contract OR Remote OR Part-time OR Freelance) NOT (\"Full-time\" OR Permanent)"
            STRATEGY="SDET Specialist. Focus on Cypress/Python frameworks - CONTRACT/REMOTE ONLY"
            ;;
        1)
            # Focus: QAOps / Linux Infrastructure - EXCLUDE FULL-TIME
            SELECTED_QUERY="(\"Senior QA\" OR \"Automation Engineer\") AND (Bash OR Shell OR Linux OR DevOps) AND (Contract OR Remote OR Part-time OR Freelance) NOT (\"Full-time\" OR Permanent)"
            STRATEGY="QAOps/Linux Specialist - CONTRACT/REMOTE ONLY"
            ;;
        2)
            # Focus: Domain Expertise (Payroll, POS, Salesforce) - EXCLUDE FULL-TIME
            SELECTED_QUERY="(\"Senior QA\" OR \"Software Tester\") AND (Payroll OR POS OR Salesforce OR \"E-commerce\") AND (Contract OR Remote OR Part-time OR Freelance) NOT (\"Full-time\" OR Permanent)"
            STRATEGY="Domain Expert - CONTRACT/REMOTE ONLY"
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
