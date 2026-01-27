#!/usr/bin/env bash

# --- CONFIG ---
API_KEY="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"
MODEL="llama-3.3-70b-versatile" 
LAST_SENT=0
COOLDOWN=30 # Seconds to wait between AI calls

SYSTEM_PROMPT="Act as a cynical, elite AI observer. Summarize chat drama with brutal brevity. 
Format:
- PLAYERS: [Names + Vibe]
- SUBTEXT: [1 sentence on the hidden ego/pathos]
- ANALOGY: [1 sharp historical/pop-culture reference]
Constraints: No fluff. Max 60 words total. Tone: Dry, judgmental."

echo "Observer is watching with a ${COOLDOWN}s cooldown..."

dbus-monitor "interface='org.freedesktop.Notifications'" | \
grep --line-buffered "string" | \
while read -r line; do

    clean_line="${line%\"}"
    clean_line="${clean_line#\"}"
    
    # Skip the system noise immediately
    case "$clean_line" in 
        "image_data"|"variant"|"plasma_workspace"|"string"|"urgency"|"x-kde-"*|"notification"|"desktop-entry"|"sender-pid")
            continue ;;
    esac

    CHUNK+="$clean_line | "

    # TRIGGER on Discord notifications
    if [[ "$clean_line" == *"com.discordapp.Discord"* ]]; then
        
        # Check if we are still in cooldown
        CURRENT_TIME=$(date +%s)
        ELAPSED=$(( CURRENT_TIME - LAST_SENT ))

        if [[ $ELAPSED -lt $COOLDOWN ]]; then
            echo "Skipping... Cooldown active ($(( COOLDOWN - ELAPSED ))s remaining)"
            CHUNK="" # Clear buffer so we don't send stale drama later
            continue
        fi

        # Filter the junk before sending to AI
        CLEAN_CHAT=$(echo "$CHUNK" | sed -E 's/com.discordapp.Discord | //g')

        if [[ ${#CLEAN_CHAT} -gt 20 ]]; then
            
            PAYLOAD=$(jq -n \
                --arg sys "$SYSTEM_PROMPT" \
                --arg usr "$CLEAN_CHAT" \
                --arg mod "$MODEL" \
                '{model: $mod, messages: [{role: "system", content: $sys}, {role: "user", content: $usr}], temperature: 0.7}')

            RAW_JSON=$(curl -s https://api.groq.com/openai/v1/chat/completions \
              -H "Authorization: Bearer $API_KEY" \
              -H "Content-Type: application/json" \
              -d "$PAYLOAD")

            AI_CONTENT=$(echo "$RAW_JSON" | jq -r '.choices[0].message.content // .error.message')

            # Update the last sent timestamp
            LAST_SENT=$(date +%s)

            kdialog --title "Observer Insight ($(date +"%I:%M %p"))" \
                    --msgbox "$AI_CONTENT" 2>/dev/null &
            
            echo -e "\n--- INSIGHT GENERATED ---\n$AI_CONTENT\n------------------------"
        fi

        CHUNK="" 
    fi
done
