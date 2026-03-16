#!/usr/bin/env bash

# ─────────────────────────────────────────────────────────────────
#  Discord Science & Tech Scout – v4.8 (Sensitive Edition)
# ─────────────────────────────────────────────────────────────────

# Load API Key
GROQ_API_KEY=$(tr -d '[:space:]' < ~/.config/groq_api_key.txt) || { 
    echo "Error: Cannot read API key." >&2; exit 1 
}

MODEL="llama-3.3-70b-versatile" 
COOLDOWN=60               
COOLDOWN_FILE="/tmp/discord-observer-cooldown"
touch "$COOLDOWN_FILE"

# --- LAYER 1: UPDATED SENSITIVE GATEKEEPER ---
# Catches common scientific discussion terms to trigger Grok analysis.
INTEREST_REGEX="(breakthrough|discovery|invention|innovation|solution|optimized|patent|eureka|proof|prototype|research|peer-review|novel|method|github|http|doi\.org|arxiv|nature\.com|science\.org|quantum|superconductor|fusion|fission|particle|entropy|thermo|relativity|nano|graphene|crispr|genome|enzyme|molecule|catalyst|synthesis|reaction|biotech|clinical|vaccine|neuro|pathogen|climate|decarbon|renewable|sequestration|carbon|satellite|algorithm|neural|llm|encryption|blockchain|architecture|theory|mechanism|reactor|electricity|experiment|hypothesis|physics|chemistry|biology|medicine|engineering)"

# --- LAYER 2: GROK SYSTEM PROMPT ---
SYSTEM_PROMPT="Act as an elite AI Science Curator. 
TASK: Analyze the chat for significant intellectual signals: breakthroughs, inventions, or novel scientific ideas.
IF MUNDANE (jokes, food, tech support, general chat): Respond ONLY with 'IGNORE'. 
IF INTERESTING: Provide DISCOVERY, FIELD, POTENTIAL, and a sophisticated VERDICT.
Constraints: 8/10 significance threshold. Max 150 words."

echo "Sensitive Scout Active. Filtering for signal..."

CHUNK=""

# ─────────────────────────────────────────────────────────────────
# Main Monitoring Loop
# ─────────────────────────────────────────────────────────────────

dbus-monitor "interface='org.freedesktop.Notifications'" 2>/dev/null | \
grep --line-buffered "string" | \
while read -r line; do
    
    # Extract raw content
    clean=$(echo "$line" | sed -E 's/^.*string[[:space:]]+"//; s/"[[:space:]]*$//; s/\\"/"/g')

    # SILENCE THE NOISE: Skip system strings and common Discord clutter
    case "$clean" in
        ""|"default"|"image_data"|"variant"|"plasma_workspace"|"urgency"|"x-kde-"*|"notification"|"desktop-entry"|"sender-pid"|"System Notifications"|"start-here-kde-plasma")
            continue ;;
    esac

    # Accumulate history
    CHUNK+="$clean | "
    [[ ${#CHUNK} -gt 5000 ]] && CHUNK="${CHUNK: -5000}"

    # Only process when a message actually comes from Discord
    if [[ "$line" == *"com.discordapp.Discord"* ]]; then
        
        # --- FIRST LAYER CHECK ---
        LOWER_MSG=$(echo "$clean" | tr '[:upper:]' '[:lower:]')
        if [[ ! "$LOWER_MSG" =~ $INTEREST_REGEX ]]; then
            continue 
        fi

        # --- COOLDOWN CHECK ---
        CURRENT_TIME=$(date +%s)
        LAST_SENT=$(cat "$COOLDOWN_FILE" 2>/dev/null || echo "0")
        if (( CURRENT_TIME - LAST_SENT < COOLDOWN )); then
            continue
        fi

        echo "Potential signal detected: '$clean'. Consulting Grok..."

        # Prepare payload
        CLEAN_CHAT=$(echo "$CHUNK" | sed -E 's/com\.discordapp\.Discord//g; s/\|+/|/g; s/^[ |]+//')
        PAYLOAD=$(jq -cn --arg mod "$MODEL" --arg sys "$SYSTEM_PROMPT" --arg usr "$CLEAN_CHAT" \
            '{model: $mod, messages: [{role: "system", content: $sys}, {role: "user", content: $usr}], temperature: 0.3, max_tokens: 450}')

        # --- API CALL WITH RATE-LIMIT HANDLING ---
        ATTEMPT=0
        while [ $ATTEMPT -lt 2 ]; do
            RAW=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" \
                -H "Authorization: Bearer $GROQ_API_KEY" \
                -H "Content-Type: application/json" \
                -d "$PAYLOAD" "https://api.groq.com/openai/v1/chat/completions")

            HTTP_STATUS=$(echo "$RAW" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
            BODY=$(echo "$RAW" | sed -e 's/HTTPSTATUS\:.*//')

            if [ "$HTTP_STATUS" -eq 200 ]; then
                AI_RESPONSE=$(echo "$BODY" | jq -r '.choices[0].message.content // empty')
                break
            elif [ "$HTTP_STATUS" -eq 429 ]; then
                echo "Rate limited. Waiting 25s..."
                sleep 25
                ((ATTEMPT++))
            else
                echo "Error: Status $HTTP_STATUS"
                break
            fi
        done

        # --- OUTPUT VERDICT ---
        if [[ -n "$AI_RESPONSE" && "$AI_RESPONSE" != *"IGNORE"* ]]; then
            date +%s > "$COOLDOWN_FILE"
            
            # Send Desktop Notification
            kdialog --title "Breakthrough Detected" --msgbox "$AI_RESPONSE" 2>/dev/null &
            
            # Terminal Output
            echo -e "\n💎 [SIGNAL ANALYSIS]\n$AI_RESPONSE\n────────────────────────────────"
        else
            echo "Grok analysis: Not significant. (Ignored)"
        fi
        
        CHUNK="" # Clear buffer to stay fresh
    fi
done
