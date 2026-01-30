#!/usr/bin/env bash

# --- PATHS ---
CONFIG_FILE="$HOME/.config/news-monitor"
HISTORY_FILE="$HOME/.cache/news_history.log"
LOGFILE="$HOME/scriptlogs/news_monitor.log"

# High-signal topics for breakthrough discovery
TOPICS=(
    "Quantum Computing" "Nuclear Fusion" "Nanotechnology" 
    "Astrophysics" "Genetics CRISPR" "Medicine" 
    "Mathematics Proof" "Artificial General Intelligence"
    "Materials Science" "Space Exploration"
)

# 1. Load API Key
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE" || exit 1
touch "$HISTORY_FILE"
mkdir -p "$(dirname "$LOGFILE")"

echo "Discovery Monitor Active. Checking for high-signal breakthroughs..."

while true; do
    for TOPIC in "${TOPICS[@]}"; do
        # Boolean Query: (Topic AND breakthrough) OR (Topic AND discovery)
        QUERY="(\"$TOPIC\" AND breakthrough) OR (\"$TOPIC\" AND discovery) -stock -price -market"
        
        # URL encoding using Python for special characters
        ENCODED_QUERY=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$QUERY'''))")

        # Fetch 10 results sorted by Relevancy
        RESPONSE=$(curl -s "https://newsapi.org/v2/everything?q=$ENCODED_QUERY&language=en&pageSize=10&sortBy=relevancy&apiKey=$NEWS_API_KEY")

        STATUS=$(echo "$RESPONSE" | jq -r '.status')
        if [[ "$STATUS" != "ok" ]]; then
            echo "$(date) - API Error ($TOPIC): $(echo "$RESPONSE" | jq -r '.message')" >> "$LOGFILE"
            continue
        fi

        # 2. Process results
        for i in {0..9}; do
            TITLE=$(echo "$RESPONSE" | jq -r ".articles[$i].title")
            URL=$(echo "$RESPONSE" | jq -r ".articles[$i].url")
            DESC=$(echo "$RESPONSE" | jq -r ".articles[$i].description")
            SOURCE=$(echo "$RESPONSE" | jq -r ".articles[$i].source.name")

            [[ "$TITLE" == "null" || -z "$TITLE" ]] && break

            # --- THE JUNK FILTER ---
            # Skips articles shorter than 200 characters (stubs/placeholders)
            DESC_LEN=${#DESC}
            if [ "$DESC_LEN" -lt 200 ]; then
                continue
            fi

            # 3. History Check (Zero-Miss Logic)
            if ! grep -q "$URL" "$HISTORY_FILE"; then
                echo "$URL" >> "$HISTORY_FILE"
                echo "$(date) - New $TOPIC Discovery [$SOURCE]: $TITLE" >> "$LOGFILE"

                # Send clickable notification
                notify-send -u critical -t 0 "🧠 $TOPIC Breakthrough" "$TITLE\n\nSource: $SOURCE\n\n<a href=\"$URL\">Click here to read full source</a>" &
                
                sleep 2
            fi
        done
        
        # Rate limit safety
        sleep 15
    done

    # Maintenance: Keep history log at last 1000 entries
    tail -n 1000 "$HISTORY_FILE" > "$HISTORY_FILE.tmp" && mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"

    echo "Cycle complete. Sleeping 1 hour..."
    sleep 20m
done
