#!/bin/bash

# --- CONFIGURATION ---
BIN_DIR="$HOME/Documents/bin"
SEEN_FILE="$BIN_DIR/seen_jobs.txt"
LOG_FILE="$BIN_DIR/job_search.log"
TEMPLATE_FILE="$BIN_DIR/current_template.txt"
ALERT_EMAIL="cabpacedilla@gmail.com"

# Ensure directory and files exist
mkdir -p "$BIN_DIR"
touch "$SEEN_FILE"

# --- AUTO-MAINTENANCE: Clear memory on the 1st of the month ---
CURRENT_DAY=$(date +%d)
if [[ "$CURRENT_DAY" == "01" ]]; then
    echo "$(date): Monthly maintenance - Clearing seen_jobs.txt" >> "$LOG_FILE"
    > "$SEEN_FILE"
fi

echo "Job Search Engine Active. Press Ctrl+C to stop."

while true; do
    echo "------------------------------------------------" >> "$LOG_FILE"
    echo "$(date): Starting new search cycle..." >> "$LOG_FILE"

    # --- ROTATING QUERIES ---
    DAY_OF_YEAR=$(date +%j)
    QUERY_INDEX=$((DAY_OF_YEAR % 3))

    case $QUERY_INDEX in
        0)
            # Focus: Automation & Frameworks (Adding Cypress & JavaScript)
            SELECTED_QUERY="(\"Senior QA\" OR SDET) AND (Python OR Cypress OR Javascript) AND (Selenium OR Automation) AND (Linux OR Bash)"
            STRATEGY="Focus: Technical Breadth. Mention building frameworks in both Python and JS (Cypress), and your Linux daily-driver setup."
            INTRO="Senior SDET with 8+ years experience. I build robust automation suites using Python and Cypress, optimized for Linux environments."
            ;;
        1)
            # Focus: Leadership, Strategy & DevOps (Adding CI/CD tools)
            SELECTED_QUERY="(\"QA Lead\" OR \"QA Manager\" OR \"Test Lead\") AND (\"Test Strategy\" OR \"CI/CD\" OR Docker OR Jenkins) AND Linux"
            STRATEGY="Focus: Leadership & QAOps. Highlight directed QA operations, GitHub integration, and CircleCI pipeline optimization."
            INTRO="Senior QA Leader specialized in optimizing delivery speed through workflow coordination, GitHub integration, and CI/CD quality gates."
            ;;
        2)
            # Focus: Specialized Domains & API (Adding Payroll, POS, and Postman)
            SELECTED_QUERY="(\"Senior QA\" OR \"Software Tester\") AND (Payroll OR POS OR \"E-commerce\") AND (Postman OR API OR SQL)"
            STRATEGY="Focus: Domain Expertise. Emphasize your deep experience with Payroll logic, POS systems, and API validation."
            INTRO="Senior QA Engineer with specialized expertise in Payroll, POS, and E-commerce systems, featuring heavy API and SQL backend validation."
            ;;
    esac

    # --- EXECUTION ---
    # timeout 120s prevents the process from hanging indefinitely
    RAW_RESULTS=$(timeout 120s python3 "$BIN_DIR/find_jobs.py" "$SELECTED_QUERY")
    
    NEW_JOBS_BODY=""
    COUNT=0

    while read -r line; do
        # Ignore empty lines and Python DEBUG/Error messages
        [[ -z "$line" || "$line" == DEBUG* || "$line" == Traceback* ]] && continue
        
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

    # --- EMAIL DISPATCH ---
    if [[ -n "$NEW_JOBS_BODY" ]]; then
        SUBJECT="[$COUNT New] Senior QA Roles Found"
        {
            echo "To: $ALERT_EMAIL"
            echo "Subject: $SUBJECT"
            echo "Content-Type: text/plain; charset=UTF-8"
            echo ""
            echo -e "Hi Claive,\n\nI found $COUNT new matches.\n\n$NEW_JOBS_BODY\n---\nStrategy: $STRATEGY"
        } | msmtp -a default "$ALERT_EMAIL"
        echo "$(date): Sent email for $COUNT jobs." >> "$LOG_FILE"
    fi

    # --- SLEEP ---
    MINS=$(( (RANDOM % 21) + 55 ))
    echo "$(date): Cycle complete. Sleeping for $MINS minutes..." >> "$LOG_FILE"
    sleep "${MINS}m"
done
