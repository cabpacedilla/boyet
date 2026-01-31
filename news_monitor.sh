#!/usr/bin/env bash

# --- PATHS ---
CONFIG_FILE="$HOME/.config/news-monitor"
HISTORY_FILE="$HOME/.cache/news_history.log"
LOGFILE="$HOME/scriptlogs/news_monitor.log"

# 1. Load API Key
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE" || exit 1
touch "$HISTORY_FILE"

while true; do
    # COMBINED QUERY: One request to rule them all
    # This searches for Science OR Tech breakthroughs in a single "touch"
    QUERY="(Science OR Technology OR Physics OR Math) AND (breakthrough OR discovery) -stock -price"
    ENCODED_QUERY=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$QUERY'''))")

    RESPONSE=$(curl -s "https://newsapi.org/v2/everything?q=$ENCODED_QUERY&language=en&pageSize=15&sortBy=publishedAt&apiKey=$NEWS_API_KEY")

    # Check for Rate Limit Error
    STATUS=$(echo "$RESPONSE" | jq -r '.status')
    CODE=$(echo "$RESPONSE" | jq -r '.code')

    if [[ "$STATUS" == "error" ]]; then
        if [[ "$CODE" == "rateLimited" ]]; then
            echo "$(date) - RATE LIMITED! Entering 6-hour hibernation..." >> "$LOGFILE"
            sleep 6h  # Stop touching the API to let the quota reset
            continue
        fi
        echo "$(date) - API Error: $(echo "$RESPONSE" | jq -r '.message')" >> "$LOGFILE"
        sleep 1h
        continue
    fi

    # 2. Process results (scanning top 15)
    for i in {0..14}; do
        TITLE=$(echo "$RESPONSE" | jq -r ".articles[$i].title")
        URL=$(echo "$RESPONSE" | jq -r ".articles[$i].url")
        DESC=$(echo "$RESPONSE" | jq -r ".articles[$i].description")

        [[ "$TITLE" == "null" || -z "$TITLE" ]] && break
        [[ ${#DESC} -lt 200 ]] && continue

        if ! grep -q "$URL" "$HISTORY_FILE"; then
            echo "$URL" >> "$HISTORY_FILE"
            notify-send -u critical -t 0 "🧠 New Discovery" "$TITLE\n\n<a href=\"$URL\">Read More</a>" &
            sleep 2
        fi
    done

    # 3. Safe Sleep (With 1 request per cycle, 15m is very safe)
    echo "Cycle complete. Total requests today are safe. Sleeping 20m..."
    sleep 20m
done
