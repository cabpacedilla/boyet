#!/usr/bin/env bash
export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
# Multi-script monitor: ensures scripts in SCRIPTS array are running,
# kills extras, and notifies if missing.

set -o pipefail

# --- Secure lock ---
if [[ -z "${XDG_RUNTIME_DIR:-}" || ! -d "$XDG_RUNTIME_DIR" ]]; then
    echo "ERROR: XDG_RUNTIME_DIR unavailable" >&2
    exit 1
fi
LOCK_FILE="$XDG_RUNTIME_DIR/checkservices.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    exit 1
fi
printf '%s\n' "$$" >&9

cleanup() {
    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
}
trap cleanup EXIT

# Base scripts that do NOT require internet (always run)
SCRIPTS=(
    "autosync"
    "autobrightness"
    "backlisten"
    "batteryAlertBashScript"
    "btrfs_balance_quarterly"
    "btrfs_scrub_monthly"
    "fortune4you"
    "keyLocked"
    "laptopLid_close"
    "login_monitor"
    "low_disk_space"
    "lowMemAlert"
    "power_usage"
    "runscreensaver"
    "security_check"
)

COOLDOWN=30   # seconds between checks
MIN_INSTANCES=1

# --- Function to check Internet connectivity ---
# ============================================================
# INTERNET CHECK (OPTIMIZED)
# ============================================================
# Caches the result for INTERNET_CACHE_TTL seconds to avoid
# hammering the network every loop iteration.
# ============================================================
INTERNET_CACHE_TTL=30          # Seconds to trust a positive result
INTERNET_CHECK_TIMEOUT=4       # Per-endpoint timeout (was 10)
INTERNET_DNS_TIMEOUT=2         # DNS resolution timeout

_internet_last_check=0
_internet_last_result=1        # 1 = offline, 0 = online (start pessimistic)

check_internet() {
    local now
    now=$(date +%s)
    
    # --- Cache: if we checked recently and were online, trust it ---
    if [ "$_internet_last_result" -eq 0 ]; then
        local age=$((now - _internet_last_check))
        if [ "$age" -lt "$INTERNET_CACHE_TTL" ]; then
            return 0
        fi
    fi
    
    # --- Fast DNS check first (cheap, catches most failures) ---
    if ! timeout "$INTERNET_DNS_TIMEOUT" getent hosts one.one.one.one >/dev/null 2>&1; then
        # DNS failed — but try a hardcoded IP to distinguish DNS vs. no route
        if ! timeout "$INTERNET_DNS_TIMEOUT" curl -fsI \
                --connect-timeout 2 --max-time 3 \
                "https://1.1.1.1" >/dev/null 2>&1; then
            _internet_last_check=$now
            _internet_last_result=1
            return 1
        fi
    fi
    
    # --- Parallel endpoint checks ---
    local endpoints=(
        "https://1.1.1.1"                    # Cloudflare DNS (IP, no DNS needed)
        "https://www.google.com/generate_204" # Google 204 (tiny response)
        "https://www.cloudflare.com/cdn-cgi/trace"
    )
    
    local pids=()
    local tmpdir
    tmpdir=$(mktemp -d)
    
    local i=0
    for endpoint in "${endpoints[@]}"; do
        (
            if curl -fsI \
                --connect-timeout 2 \
                --max-time "$INTERNET_CHECK_TIMEOUT" \
                --no-keepalive \
                -H "User-Agent: Mozilla/5.0" \
                "$endpoint" >/dev/null 2>&1; then
                echo "ok" > "$tmpdir/result_$i"
            fi
        ) &
        pids+=($!)
        i=$((i + 1))
    done
    
    # Wait for any to succeed
    local success=1
    for _ in $(seq 1 "$INTERNET_CHECK_TIMEOUT"); do
        for f in "$tmpdir"/result_*; do
            if [ -f "$f" ] && [ "$(cat "$f")" = "ok" ]; then
                success=0
                break 2
            fi
        done
        sleep 0.5
    done
    
    # Clean up
    kill "${pids[@]}" 2>/dev/null
    wait "${pids[@]}" 2>/dev/null
    rm -rf "$tmpdir"
    
    _internet_last_check=$now
    _internet_last_result=$success
    return $success
}

# --- Main loop ---
while true; do
    # 1. Start with base scripts
    ACTIVE_SCRIPTS=("${SCRIPTS[@]}")
    
    # 2. Define scripts that REQUIRE an internet connection
    INTERNET_REQUIRED=(
        "weather_alarm"
        "job_rotate"
    )

    # 3. Connectivity Logic
    if check_internet; then
        # Online: Add internet-dependent scripts to the active list
        for script in "${INTERNET_REQUIRED[@]}"; do
            ACTIVE_SCRIPTS+=("$script")
        done
    else
        # Offline: Filter out internet scripts and kill running instances
        for script in "${INTERNET_REQUIRED[@]}"; do
            # Remove from the array using pattern substitution
            ACTIVE_SCRIPTS=("${ACTIVE_SCRIPTS[@]/$script/}")
            
            # Identify and kill offline processes
            SCRIPT_FNAME="${script}.sh"
            
            PROCS=($(pgrep -f "bash $SCRIPT_PATH"))
            #PROCS=($(pgrep -f "$SCRIPT_BASENAME"))
            if [[ -n "$PIDS" ]]; then
                for pid in $PIDS; do
                    kill "$pid"
                    notify-send -t 5000 -u critical --app-name "💀 CheckServices" "$SCRIPT_FNAME killed: No internet connection." &
                done
            fi
        done
    fi

    # 4. Process Management Loop
    for SCRIPT_BASENAME in "${ACTIVE_SCRIPTS[@]}"; do
        # Clean up empty indices (from the removal logic above)
        [[ -z "$SCRIPT_BASENAME" ]] && continue
        
        SCRIPT_NAME="${SCRIPT_BASENAME}.sh"
        SCRIPT_PATH="$HOME/Documents/bin/$SCRIPT_NAME"

        # Check for existence
        if [ ! -x "$SCRIPT_PATH" ]; then
            notify-send --app-name "CheckServices" "$SCRIPT_NAME not found or not executable!" &
            continue
        fi

        # Process control – match by full script path (robust)
        PROCS=($(pgrep -f "bash $SCRIPT_PATH"))
        #PROCS=($(pgrep -f "$SCRIPT_BASENAME"))
        NUM_RUNNING=${#PROCS[@]}

        if [ "$NUM_RUNNING" -gt "$MIN_INSTANCES" ]; then
            # Keep newest instance, kill oldest to ensure freshness
            PIDS_TO_KILL=$(ps -o pid= --sort=start_time -p "${PROCS[@]}" | head -n -$MIN_INSTANCES)
            for pid in $PIDS_TO_KILL; do
                kill "$pid"
                notify-send -t 5000 --app-name "💀 CheckServices" "Extra $SCRIPT_NAME killed: PID $pid" &
            done
        elif [ "$NUM_RUNNING" -lt "$MIN_INSTANCES" ]; then
            # Respawn missing services
            bash "$SCRIPT_PATH" &
            notify-send -t 5000 --app-name "✅ CheckServices" "$SCRIPT_NAME started."
            sleep 2
        fi
    done

    sleep "$COOLDOWN"
done
