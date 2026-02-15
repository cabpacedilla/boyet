#!/usr/bin/env bash

# Fedora SOC Monitor v4.1 - Self-Healing EDR with Recovery Mode
# 🚨 NEW: Recovery Mode, Self-Diagnosis, Config Backup/Restore

# ===== Configuration =====
AUTO_RESPONSE_ENABLED=true
DRY_RUN=true               # Set to false after Week 1
PHASE=1                    # 1=Dry Run, 2=Partial Auto-Response, 3=Full Auto-Response
START_TIME=$(date +%s)
RECOVERY_MODE=false        # 🚨 NEW: Recovery Mode flag
LAST_SUCCESSFUL_CONFIG="$HOME/soc_monitor_last_good_config"  # 🚨 NEW: Config backup

# Whitelists (modify as needed)
PROCESS_WHITELIST=("systemd" "mysqld" "nginx" "httpd" "docker" "kubelet" "clamscan" "postgres")
IP_WHITELIST=("127.0.0.1" "10.0.0.0/8" "192.168.0.0/16" "172.16.0.0/12")
USER_WHITELIST=("root" "admin" "backup")

# Paths
LOG_DIR="$HOME/soc_monitor_logs"
YARA_RULES="$HOME/soc_monitor_yara_rules.yar"
CONFIG_BACKUP="$HOME/soc_monitor_config_backup"
mkdir -p "$LOG_DIR" "$CONFIG_BACKUP"

# 🚨 NEW: Save initial good config
save_config() {
    {
        echo "AUTO_RESPONSE_ENABLED=$AUTO_RESPONSE_ENABLED"
        echo "DRY_RUN=$DRY_RUN"
        echo "PHASE=$PHASE"
        echo "PROCESS_WHITELIST=(${PROCESS_WHITELIST[*]})"
        echo "IP_WHITELIST=(${IP_WHITELIST[*]})"
        echo "USER_WHITELIST=(${USER_WHITELIST[*]})"
    } > "$LAST_SUCCESSFUL_CONFIG"
}
save_config  # Save initial config

# ===== Core Functions =====
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_DIR/soc_monitor.log"
}

is_whitelisted_process() {
    local proc="$1"
    for w in "${PROCESS_WHITELIST[@]}"; do
        [[ "$proc" == *"$w"* ]] && return 0
    done
    return 1
}

is_whitelisted_ip() {
    local ip="$1"
    for w in "${IP_WHITELIST[@]}"; do
        [[ "$ip" == "$w" ]] || [[ "$ip" =~ $w ]] && return 0
    done
    return 1
}

is_whitelisted_user() {
    local user="$1"
    for w in "${USER_WHITELIST[@]}"; do
        [[ "$user" == "$w" ]] && return 0
    done
    return 1
}

execute_response() {
    if [[ "$RECOVERY_MODE" == true ]]; then
        log "[RECOVERY] Skipping auto-response: $2"
        return
    fi
    if [[ "$AUTO_RESPONSE_ENABLED" == true ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log "[DRY RUN] Would execute: $2 ($1)"
        else
            log "[AUTO-RESPONSE] $2"
            eval "$1" 2>/dev/null
        fi
    fi
}

rate_limit_notify() {
    local alert_key="$1"
    local msg="$2"
    local now=$(date +%s)
    if [[ ! -f "$CONFIG_BACKUP/alert_times.txt" ]] || \
       [[ $((now - $(cat "$CONFIG_BACKUP/alert_times.txt" 2>/dev/null))) -gt 300 ]]; then
        echo "$now" > "$CONFIG_BACKUP/alert_times.txt"
        echo "1" > "$CONFIG_BACKUP/alert_counts.txt"
        notify "$msg"
    else
        count=$(( $(cat "$CONFIG_BACKUP/alert_counts.txt" 2>/dev/null) + 1 ))
        echo "$count" > "$CONFIG_BACKUP/alert_counts.txt"
        if [[ $((count % 10)) -eq 0 ]]; then
            notify "$msg (repeated $count times)"
        fi
    fi
}

notify() {
    local msg=$(echo "$1" | sed 's/[^a-zA-Z0-9 :./_-]//g' | cut -c1-200)
    if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
        curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
            -d "chat_id=$TELEGRAM_CHAT_ID&text=🛡️ SOC Alert: $msg" >/dev/null 2>&1 &
    fi
}

# 🚨 NEW: Recovery Mode Functions
enter_recovery_mode() {
    log "⚠️ ENTERING RECOVERY MODE"
    RECOVERY_MODE=true
    AUTO_RESPONSE_ENABLED=false
    DRY_RUN=true

    # Restore last known good configuration
    if [[ -f "$LAST_SUCCESSFUL_CONFIG" ]]; then
        source "$LAST_SUCCESSFUL_CONFIG"
        log "✅ Restored last good configuration"
    else
        log "❌ No backup config found. Using defaults."
        PHASE=1
    fi

    # Notify admin
    notify "SYSTEM ENTERED RECOVERY MODE - Check logs for details"
}

exit_recovery_mode() {
    log "🛠️ EXITING RECOVERY MODE"
    RECOVERY_MODE=false
    save_config
}

# 🚨 NEW: Self-Diagnosis
self_diagnose() {
    local errors=0
    local diagnostics="$LOG_DIR/diagnostics.log"

    # Check system load
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | cut -d, -f1)
    if (( $(echo "$load_avg > 10" | bc -l) )); then
        log "⚠️ High system load detected: $load_avg" | tee -a "$diagnostics"
        errors=$((errors + 1))
    fi

    # Check excessive kills
    local kills=$(grep "AUTO-RESPONSE.*Killed" "$LOG_DIR/soc_monitor.log" 2>/dev/null | wc -l)
    if [[ "$kills" -gt 10 ]]; then
        log "⚠️ Excessive process kills detected: $kills" | tee -a "$diagnostics"
        errors=$((errors + 1))
    fi

    # Check blocked IPs
    local blocked_ips=$(sudo iptables -L INPUT -n | grep DROP | wc -l)
    if [[ "$blocked_ips" -gt 100 ]]; then
        log "⚠️ Excessive blocked IPs: $blocked_ips" | tee -a "$diagnostics"
        errors=$((errors + 1))
    fi

    # Check for recovery mode loops
    if [[ "$RECOVERY_MODE" == true ]]; then
        local recovery_duration=$(( ($(date +%s) - $(stat -c %Y "$diagnostics" 2>/dev/null)) / 60 ))
        if [[ "$recovery_duration" -gt 60 ]]; then  # Stuck in recovery >1 hour
            log "⚠️ Stuck in recovery mode for $recovery_duration minutes" | tee -a "$diagnostics"
            errors=$((errors + 1))
        fi
    fi

    # Enter recovery if too many errors
    if [[ "$errors" -gt 1 && "$RECOVERY_MODE" == false ]]; then
        enter_recovery_mode
    elif [[ "$errors" -eq 0 && "$RECOVERY_MODE" == true ]]; then
        exit_recovery_mode
    fi
}

# ===== Auto-Maintenance Functions =====
update_yara_rules() {
    log "🔄 Updating YARA rules..."
    if curl -s "https://raw.githubusercontent.com/Yara-Rules/rules/master/malware/index.yar" -o "$YARA_RULES" 2>/dev/null; then
        log "✅ YARA rules updated."
        save_config
    else
        log "❌ Failed to update YARA rules. Using cached version."
    fi
}

review_whitelists() {
    log "🔍 Reviewing whitelists..."
    {
        echo "=== Whitelist Review $(date) ==="
        echo "High-CPU Processes:"
        grep "HIGH_CPU" "$LOG_DIR/soc_monitor.log" 2>/dev/null | awk '{print $NF}' | sort | uniq -c | sort -nr | head -5
        echo -e "\nInternal IPs:"
        grep -E "10\.[0-9]+\.[0-9]+\.[0-9]+" "$LOG_DIR/soc_monitor.log" 2>/dev/null | grep -Eo '10\.[0-9]+\.[0-9]+\.[0-9]+' | sort | uniq -c | sort -nr | head -5
        echo -e "\nNew Users:"
        grep "New login detected" "$LOG_DIR/soc_monitor.log" 2>/dev/null | awk '{print $NF}' | sort | uniq -c | sort -nr | head -5
    } >> "$LOG_DIR/whitelist_review.log"

    # Auto-approve frequent internal IPs
    grep -E "10\.[0-9]+\.[0-9]+\.[0-9]+" "$LOG_DIR/soc_monitor.log" 2>/dev/null | grep -Eo '10\.[0-9]+\.[0-9]+\.[0-9]+' | sort | uniq -c | sort -nr | \
    while read -r count ip; do
        if [[ "$count" -gt 10 && ! " ${IP_WHITELIST[@]} " =~ " $ip " ]]; then
            log "✅ Auto-approving internal IP: $ip"
            IP_WHITELIST+=("$ip")
            save_config
        fi
    done
}

test_failover() {
    log "🧪 Running failover tests..."

    # Test 1: Simulate auditd crash (if running)
    if systemctl is-active --quiet auditd 2>/dev/null; then
        sudo systemctl stop auditd 2>/dev/null
        sleep 10
        sudo systemctl start auditd 2>/dev/null
        sleep 5
    fi

    # Test 2: Simulate rootkit artifact
    sudo touch /dev/.test_artifact 2>/dev/null
    sleep 10
    sudo rm -f /dev/.test_artifact 2>/dev/null
    sleep 5

    # Test 3: Simulate high-CPU process
    timeout 5 nice -n 19 yes > /dev/null 2>&1 &
    sleep 5
}

rotate_logs() {
    log "🗃️ Rotating logs..."
    find "$LOG_DIR" -name "*.log" -type f -size +10M -exec gzip {} \;
    find "$LOG_DIR" -name "*.gz" -mtime +30 -delete
    save_config
}

# ===== Phase Management =====
manage_phases() {
    local days_running=$(( ($(date +%s) - START_TIME) / 86400 ))
    case $PHASE in
        1)
            if [[ "$days_running" -ge 7 ]]; then
                PHASE=2
                DRY_RUN=false
                log "📅 Transitioned to Phase 2 (Partial Auto-Response)"
                save_config
            fi
            ;;
        2)
            if [[ "$days_running" -ge 14 ]]; then
                PHASE=3
                log "📅 Transitioned to Phase 3 (Full Auto-Response)"
                save_config
            fi
            ;;
    esac
}

# ===== Main Monitoring Functions =====
monitor_processes() {
    ps aux --sort=-%cpu 2>/dev/null | awk '
        BEGIN {IGNORECASE=1}
        $3 > 80.0 {print "HIGH_CPU: " $11 " (CPU: " $3 "%)|" $2}
        $3 > 50.0 && $3 <= 80.0 {print "MEDIUM_CPU: " $11 " (CPU: " $3 "%)|" $2}
        $11 ~ /(\/tmp\/|\/dev\/shm\/|\/run\/user\/|\/var\/tmp\/|\/proc\/)/ {print "SUSPICIOUS_PATH: " $11 "|" $2}
        $11 ~ /(minerd|xmrig|cryptonight|kdevtmpfsi|cpuminer|ccminer|egminer|sgminer|bfgminer|cgminer)/ {print "MINER: " $11 "|" $2}
        $11 ~ /(nc|netcat|ncat).* (-e|\/bin\/bash|\/bin\/sh)/ {print "REVERSE_SHELL: " $11 "|" $2}
    ' | while IFS='|' read -r alert pid; do
        case $alert in
            HIGH_CPU*)
                proc=$(ps -p "$pid" -o comm= 2>/dev/null)
                if ! is_whitelisted_process "$proc"; then
                    log "[HIGH] PROCESS: $alert"
                    if [[ "$PHASE" -ge 2 && "$RECOVERY_MODE" == false ]]; then
                        execute_response "sudo kill -9 $pid" "Killed high-CPU process (PID: $pid)"
                    fi
                fi
                ;;
            MINER*)
                log "[CRITICAL] PROCESS: $alert"
                if [[ "$PHASE" -ge 2 && "$RECOVERY_MODE" == false ]]; then
                    execute_response "sudo kill -9 $pid" "Killed crypto miner (PID: $pid)"
                fi
                ;;
            REVERSE_SHELL*)
                log "[CRITICAL] PROCESS: $alert"
                if [[ "$PHASE" -ge 2 && "$RECOVERY_MODE" == false ]]; then
                    execute_response "sudo kill -9 $pid" "Killed reverse shell (PID: $pid)"
                fi
                ;;
        esac
    done
}

monitor_network() {
    # Check for suspicious ports
    ss -tulpn 2>/dev/null | grep LISTEN | awk '{print $5}' | sort -u | while read -r port; do
        if [[ "$port" =~ :(31337|4444|5555|6666|7777|8888) ]]; then
            ip=$(echo "$port" | cut -d: -f1)
            if ! is_whitelisted_ip "$ip"; then
                log "[HIGH] NETWORK: Suspicious port $port"
                if [[ "$PHASE" -ge 3 && "$RECOVERY_MODE" == false ]]; then
                    execute_response "sudo iptables -A INPUT -s $ip -j DROP" "Blocked IP $ip"
                fi
            fi
        fi
    done

    # Check for brute force attempts
    if command -v fail2ban-client &>/dev/null; then
        sudo fail2ban-client status sshd 2>/dev/null | grep "Banned IP" | while read -r line; do
            ip=$(echo "$line" | awk '{print $NF}')
            log "[MEDIUM] NETWORK: fail2ban blocked $ip"
        done
    fi
}

# ===== Main Loop =====
log "🚀 Starting SOC Monitor v4.1 (Self-Healing EDR with Recovery Mode)"
log "📅 Phase: $PHASE | Auto-Response: $AUTO_RESPONSE_ENABLED | Dry Run: $DRY_RUN | Recovery: $RECOVERY_MODE"

while true; do
    # 🚨 NEW: Self-diagnosis every 5 minutes
    if [[ $(( ($(date +%s) - START_TIME) % 300 )) -eq 0 ]]; then
        self_diagnose
    fi

    # Phase management (daily check)
    if [[ $(( ($(date +%s) - START_TIME) % 86400 )) -eq 0 ]]; then
        manage_phases
    fi

    # Core monitoring (every 30 seconds)
    monitor_processes
    monitor_network

    # Auto-maintenance tasks (scheduled intervals)
    local now=$(date +%s)
    local days_running=$(( (now - START_TIME) / 86400 ))

    # YARA updates (every 30 days at 3 AM)
    if [[ $((days_running % 30)) -eq 0 && $(( (now % 86400) / 3600 )) -eq 3 ]]; then
        update_yara_rules
    fi

    # Whitelist review (every 90 days at 4 AM)
    if [[ $((days_running % 90)) -eq 0 && $(( (now % 86400) / 3600 )) -eq 4 ]]; then
        review_whitelists
    fi

    # Failover test (every 90 days at 5 AM)
    if [[ $((days_running % 90)) -eq 0 && $(( (now % 86400) / 3600 )) -eq 5 ]]; then
        test_failover
    fi

    # Log rotation (daily at 6 AM)
    if [[ $(( (now % 86400) / 3600 )) -eq 6 ]]; then
        rotate_logs
    fi

    sleep 30  # Main loop interval
done
