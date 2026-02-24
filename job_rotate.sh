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
    # Priority: Software Testing Titles & Methodology
    DAY_OF_YEAR=$(date +%j)
    QUERY_INDEX=$((DAY_OF_YEAR % 3))

    case $QUERY_INDEX in
        0)
            # Focus: Automation Engineering & Development
            SELECTED_QUERY="(SDET OR \"Automation Engineer\" OR \"Quality Engineer\") AND (Python OR API OR Selenium) AND (Linux OR Bash)"
            STRATEGY="Focus on SDET/Automation: Emphasize your ability to write clean, maintainable test code in Python and shell scripts."
            INTRO="As a Senior SDET, I specialize in building automated frameworks from the ground up, with a heavy focus on backend and API validation."
            ;;
        1)
            # Focus: Strategy, Leadership, and DevOps Testing
            SELECTED_QUERY="(\"QA Lead\" OR \"Test Lead\" OR \"QA Manager\") AND (\"Test Strategy\" OR \"CI/CD\" OR \"QAOps\") AND Linux"
            STRATEGY="Focus on Leadership/Strategy: Highlight your experience in optimizing the QA life cycle and integrating tests into DevOps pipelines."
            INTRO="With over 8 years of experience in QA leadership, I focus on building robust test pipelines and optimizing workflows to ensure high-velocity, high-quality releases."
            ;;
        2)
            # Focus: Specialized Systems & Performance Testing
            SELECTED_QUERY="(\"Senior Software Tester\" OR \"Systems Test Engineer\") AND (\"Performance Testing\" OR \"Integration Testing\" OR \"Backend\") AND Bash"
            STRATEGY="Focus on Systems/Manual-to-Auto: Highlight your deep-dive testing skills, particularly in complex system integrations and POS/E-commerce."
            INTRO="I am a Senior Systems Tester with extensive experience in end-to-end integration testing and performance monitoring on Linux environments."
            ;;
    esac

    # --- EXECUTION ---
    RAW_RESULTS=$(python3 "$BIN_DIR/find_jobs.py" "$SELECTED_QUERY")
    NEW_JOBS_BODY=""
    COUNT=0

    # Use a process substitution to read results
    while read -r line; do
        [[ -z "$line" ]] && continue
        ID=$(echo "$line" | cut -d'|' -f1); TITLE=$(echo "$line" | cut -d'|' -f2)
        COMPANY=$(echo "$line" | cut -d'|' -f3); LINK=$(echo "$line" | cut -d'|' -f4)

        if ! grep -q "$ID" "$SEEN_FILE"; then
            # Using $'...' for proper newline rendering in emails
            NEW_JOBS_BODY+=$'📍 '"$TITLE"' at '"$COMPANY"$'\n🔗 '"$LINK"$'\n\n'
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
            echo -e "Hi Claive,\n\nI found $COUNT new matches for your specialized Software Testing profile.\n\n$NEW_JOBS_BODY\n---\nStrategy: $STRATEGY\n\nFull template saved to: $TEMPLATE_FILE"
        } | msmtp -a default "$ALERT_EMAIL"

        echo "$(date): Sent email for $SUBJECT" >> "$LOG_FILE"
    else
        echo "$(date): No new jobs found this cycle ($SELECTED_QUERY)." >> "$LOG_FILE"
    fi

    # --- THE SLEEP TIMER ---
    echo "$(date): Search finished. Sleeping for 3 hours..." >> "$LOG_FILE"
    sleep 3h
done
