# Create a completely clean version
#!/bin/sh
# ============================================================
# SIEM-AUDIT v1.2
#
# Correctness-first SIEM core + best-effort alerting layer
#
# RULES:
# - Core logic NEVER depends on alerts
# - Alerts are side-effect sinks only
# - POSIX /bin/sh compatible
# ============================================================

umask 077

# ------------------------------------------------------------
# CONFIG
# ------------------------------------------------------------

BASE_DIR="${HOME}/scriptlogs/siem-audit"
TRACE="scan-$(date +%Y%m%d-%H%M%S)-$$"

RAW_DIR="${BASE_DIR}/raw"
EVENT_FILE="${BASE_DIR}/events-${TRACE}.log"
STATE_FILE="${BASE_DIR}/state-${TRACE}.json"
SUMMARY_FILE="${BASE_DIR}/summary-${TRACE}.log"
EMAIL_FILE="${BASE_DIR}/email-${TRACE}.txt"

mkdir -p "$RAW_DIR" "$BASE_DIR" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "FATAL: cannot create directories" >&2
    exit 1
fi

# ------------------------------------------------------------
# STATE
# ------------------------------------------------------------

FAILURES=0
WARNINGS=0
INTERNAL_ERRORS=0

START_EPOCH=$(date +%s)

# ------------------------------------------------------------
# ALERTING (BEST EFFORT ONLY)
# ------------------------------------------------------------

notify() {
    command -v notify-send >/dev/null 2>&1 || return 0

    notify-send "SIEM Audit" "$1" >/dev/null 2>&1
    return 0
}

email_sink() {
    command -v msmtp >/dev/null 2>&1 || return 0
    msmtp "$EMAIL_TO" < "$EMAIL_FILE" >/dev/null 2>&1
    return 0
}

EMAIL_TO="cabpacedilla@gmail.com"

# ------------------------------------------------------------
# LOGGING
# ------------------------------------------------------------

log() {
    printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$SUMMARY_FILE" 2>/dev/null
}

event() {
    printf '%s|%s|%s\n' \
        "$(date '+%F %T')" \
        "$TRACE" \
        "$*" >> "$EVENT_FILE" 2>/dev/null || {
            INTERNAL_ERRORS=$((INTERNAL_ERRORS + 1))
            log "EVENT_WRITE_FAILED"
        }
}

# ------------------------------------------------------------
# COMMAND ALERT HELPERS
# ------------------------------------------------------------

alert_start() {
    notify "START: $1"
    event "notify_start:$1"
}

alert_ok() {
    notify "OK: $1"
    event "notify_ok:$1"
}

alert_fail() {
    notify "FAIL: $1"
    event "notify_fail:$1"
}

alert_final() {
    notify "FINAL: $1"
}

# ------------------------------------------------------------
# SAFE EXECUTION CORE
# ------------------------------------------------------------

run_check() {
    name="$1"
    shift

    log "START:$name"
    event "start:$name"
    alert_start "$name"

    outfile="${RAW_DIR}/${name}-${TRACE}.log"

    "$@" >"$outfile" 2>&1
    rc=$?

    log "END:$name rc=$rc"
    event "end:$name:$rc"

    if [ $rc -eq 0 ]; then
        alert_ok "$name"
        return 0
    fi

    case "$rc" in
        126|127)
            INTERNAL_ERRORS=$((INTERNAL_ERRORS + 1))
            log "INTERNAL_ERROR:$name:$rc"
            event "internal_error:$name:$rc"
            ;;
        *)
            FAILURES=$((FAILURES + 1))
            log "FAIL:$name:$rc"
            event "fail:$name:$rc"
            ;;
    esac

    alert_fail "$name"
    return $rc
}

# ------------------------------------------------------------
# TOOL CHECK
# ------------------------------------------------------------

require_tool() {
    command -v "$1" >/dev/null 2>&1 || {
        WARNINGS=$((WARNINGS + 1))
        log "MISSING_TOOL:$1"
        event "missing_tool:$1"
        notify "MISSING: $1"
        return 1
    }
    return 0
}

# ------------------------------------------------------------
# CHECKS
# ------------------------------------------------------------

check_rkhunter() {
    require_tool rkhunter || return 0
    run_check rkhunter_update sudo -n rkhunter --update --cronjob
    run_check rkhunter_scan   sudo -n rkhunter --check --cronjob
}

check_aide() {
    require_tool aide || return 0
    run_check aide_check sudo -n aide --check
}

check_chkrootkit() {
    require_tool chkrootkit || return 0
    run_check chkrootkit sudo -n chkrootkit -q
}

check_dnf() {
    require_tool dnf || return 0
    run_check dnf_history sh -c "dnf history list | head -n 10"
}

check_rpm() {
    require_tool rpm || return 0
    run_check rpm_verify sudo -n rpm -Va
}

# ------------------------------------------------------------
# STATE OUTPUT
# ------------------------------------------------------------

write_state() {
    status="$1"
    duration="$2"

    {
        printf '{\n'
        printf '  "trace": "%s",\n' "$TRACE"
        printf '  "status": "%s",\n' "$status"
        printf '  "failures": %s,\n' "$FAILURES"
        printf '  "warnings": %s,\n' "$WARNINGS"
        printf '  "internal_errors": %s,\n' "$INTERNAL_ERRORS"
        printf '  "duration_seconds": %s\n' "$duration"
        printf '}\n'
    } > "$STATE_FILE" 2>/dev/null
}

# ------------------------------------------------------------
# FINALIZATION (single authoritative decision point)
# ------------------------------------------------------------

finalize() {
    end=$(date +%s)
    duration=$((end - START_EPOCH))

    f_fail=$FAILURES
    f_warn=$WARNINGS
    f_int=$INTERNAL_ERRORS

    status="OK"

    if [ $f_int -gt 0 ]; then
        status="FAIL"
    elif [ $f_fail -gt 0 ]; then
        status="FAIL"
    elif [ $f_warn -gt 0 ]; then
        status="WARN"
    fi

    log "FINAL:$status f=$f_fail w=$f_warn i=$f_int d=$duration"
    event "final:$status:$f_fail:$f_warn:$f_int"

    write_state "$status" "$duration"

    # ----------------------------
    # FINAL ALERTING LAYER
    # ----------------------------

    alert_final "$status"

    # Email report (best-effort sink) - WITH SUBJECT LINE
    {
        # The first line becomes the email subject when using msmtp
        echo "Subject: [$status] SIEM Audit Report - $TRACE"
        echo "To: $EMAIL_TO"
        echo ""
        echo "================================================"
        echo "SIEM AUDIT REPORT"
        echo "================================================"
        echo "TRACE:           $TRACE"
        echo "STATUS:          $status"
        echo "FAILURES:        $f_fail"
        echo "WARNINGS:        $f_warn"
        echo "INTERNAL_ERRORS: $f_int"
        echo "DURATION:        ${duration}s"
        echo "================================================"
        echo ""
        echo "=== FAILURE SUMMARY ==="
        if [ $f_fail -gt 0 ]; then
            grep "FAIL:" "$SUMMARY_FILE" 2>/dev/null || echo "  (see detailed log)"
        else
            echo "  No failures detected"
        fi
        echo ""
        echo "=== DETAILED LOG ==="
        cat "$SUMMARY_FILE" 2>/dev/null
    } > "$EMAIL_FILE" 2>/dev/null

    email_sink

    # stdout summary
    printf '\nSIEM SUMMARY\n'
    printf 'Status: %s\n' "$status"
    printf 'Failures: %s\n' "$f_fail"
    printf 'Warnings: %s\n' "$f_warn"
    printf 'Internal Errors: %s\n' "$f_int"
    printf 'Duration: %ss\n' "$duration"
}

trap finalize EXIT INT TERM

# ------------------------------------------------------------
# MAIN FLOW
# ------------------------------------------------------------

log "START_SCAN:$TRACE"
event "scan_start"
notify "SCAN STARTED: $TRACE"

check_rkhunter
check_aide
check_dnf
check_rpm
check_chkrootkit

log "END_SCAN"
event "scan_end"

exit 0
