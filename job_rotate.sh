#!/bin/bash

# --- CONFIGURATION ---
BIN_DIR="$HOME/Documents/bin"
SEEN_FILE="$BIN_DIR/seen_jobs.txt"
LOG_FILE="$BIN_DIR/job_search.log"
TEMPLATE_FILE="$BIN_DIR/current_template.txt"
ALERT_EMAIL="cabpacedilla@gmail.com"
touch "$SEEN_FILE"

# Start the infinite loop
while true; do
    echo "$(date): Starting new search cycle..." >> "$LOG_FILE"

    # --- ROTATING QUERIES & TEMPLATES ---
    # Moved inside the loop so DAY_OF_YEAR updates every cycle
    DAY_OF_YEAR=$(date +%j)
    QUERY_INDEX=$((DAY_OF_YEAR % 3))

    case $QUERY_INDEX in
        0)
            SELECTED_QUERY="(SDET OR \"Senior QA\") AND (Linux OR Bash) AND (\"System Monitoring\" OR \"Automation Test\") AND (Python OR API)"
            STRATEGY="Focus on Technical Depth: Mention your Nobara daily-driver setup and how you use Bash/Python to monitor system health, not just UI."
            INTRO="As a Senior QA who maintains Linux as a daily-driver, I specialize in moving beyond UI testing into system-level automation and monitoring using Python and Bash."
            ;;
        1)
            SELECTED_QUERY="(\"Senior QA\" OR \"QA Lead\") AND (Linux OR Git) AND (\"Test Planning\" OR \"QA Pipeline\" OR \"Workflow Optimization\")"
            STRATEGY="Focus on Leadership: Mention your 8+ years of experience and your ability to optimize workflows and test coverage strategy."
            INTRO="With over 8 years of experience in QA leadership, I focus on building robust test pipelines and optimizing workflows to ensure high-velocity, high-quality releases."
            ;;
        2)
            SELECTED_QUERY="(\"Senior QA\" OR SDET) AND (Bash OR \"Shell script\") AND (\"e-commerce\" OR POS OR \"Embedded test\")"
            STRATEGY="Focus on Domain Expertise: Mention your specific background in POS and E-commerce transactional testing."
            INTRO="I bring extensive experience in the E-commerce and POS sectors, where I've specialized in testing complex transactional flows and back-end shell automation."
            ;;
    esac

    # --- EXECUTION ---
    # Ensure find_jobs.py is in the correct directory
    RAW_RESULTS=$(python3 "$BIN_DIR/find_jobs.py" "$SELECTED_QUERY")
    NEW_JOBS_BODY=""
    COUNT=0

    # Use a process substitution to read results
    while read -r line; do
        [[ -z "$line" ]] && continue
        ID=$(echo "$line" | cut -d'|' -f1); TITLE=$(echo "$line" | cut -d'|' -f2)
        COMPANY=$(echo "$line" | cut -d'|' -f3); LINK=$(echo "$line" | cut -d'|' -f4)

        if ! grep -q "$ID" "$SEEN_FILE"; then
            NEW_JOBS_BODY+="📍 $TITLE at $COMPANY\n🔗 $LINK\n\n"
            echo "$ID" >> "$SEEN_FILE"
            ((COUNT++))
        fi
    done <<< "$RAW_RESULTS"

    # --- TEMPLATE GENERATION & EMAIL ---
    if [[ -n "$NEW_JOBS_BODY" ]]; then
        # 1. Create the Quick-Reply Template
        {
            echo "--- APPLICATION STRATEGY ---"
            echo "$STRATEGY"
            echo -e "\n--- SUGGESTED OPENING ---"
            echo "$INTRO"
            echo -e "\nCheck my GitHub (boyet) for specific Linux automation scripts: https://github.com/your-github-link"
        } > "$TEMPLATE_FILE"

        # 2. Extract the first Job Title/Company for a cleaner Email Subject
        FIRST_JOB_CLEAN=$(echo -e "$NEW_JOBS_BODY" | head -n 1 | sed 's/📍 //')

        if [ "$COUNT" -gt 1 ]; then
            SUBJECT="[$COUNT] New Jobs: $FIRST_JOB_CLEAN..."
        else
            SUBJECT="New Job: $FIRST_JOB_CLEAN"
        fi

        # 3. Send the email
        {
            echo "To: $ALERT_EMAIL"
            echo "Subject: $SUBJECT"
            echo "Content-Type: text/plain; charset=UTF-8"
            echo ""
            echo -e "Hi Claive,\n\nI found $COUNT new matches for your specialized Linux/QA profile.\n\n$NEW_JOBS_BODY\n---\nStrategy: $STRATEGY\n\nFull template saved to: $TEMPLATE_FILE"
        } | msmtp -a default "$ALERT_EMAIL"

        echo "$(date): Sent email for $SUBJECT" >> "$LOG_FILE"
    else
        echo "$(date): No new jobs found this cycle." >> "$LOG_FILE"
    fi

    # --- THE SLEEP TIMER ---
    echo "$(date): Search finished. Sleeping for 3 hours..." >> "$LOG_FILE"
    sleep 3h
done
