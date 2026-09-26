#!/usr/bin/env bash
# ============================================================
# Lifecycle Test for security_check.sh (v2.2)
# ============================================================
# Process-tree-aware test harness.
# ============================================================

set -o nounset
set -o pipefail

readonly MONITOR="$HOME/Documents/bin/security_check.sh"     # ← CHANGED
readonly LOGFILE="$HOME/scriptlogs/fedora-sec-proactive.log"
readonly TEST_LOG="$HOME/scriptlogs/monitor-lifecycle-test.log"

readonly SUPERVISOR_WAIT=20
readonly STARTUP_WAIT=6

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0

log()     { echo -e "${BLUE}[TEST]${NC} $*" | tee -a "$TEST_LOG"; }
pass()    { echo -e "${GREEN}[PASS]${NC} $*" | tee -a "$TEST_LOG"; PASS=$((PASS+1)); }
fail()    { echo -e "${RED}[FAIL]${NC} $*" | tee -a "$TEST_LOG"; FAIL=$((FAIL+1)); }
info()    { echo -e "${YELLOW}[INFO]${NC} $*" | tee -a "$TEST_LOG"; }
section() { echo; echo "============================================================" | tee -a "$TEST_LOG"; echo "  $*" | tee -a "$TEST_LOG"; echo "============================================================" | tee -a "$TEST_LOG"; }

if [[ ! -x "$MONITOR" ]]; then
    echo "Monitor script not found or not executable: $MONITOR" >&2
    exit 1
fi

mkdir -p "$(dirname "$TEST_LOG")"
: > "$TEST_LOG"

MONITOR_PID=""

# ============================================================
# Process utilities
# ============================================================

descendants_of() {
    local root="$1"
    local -a result=("$root")
    local -a stack=("$root")

    while ((${#stack[@]})); do
        local current="${stack[-1]}"
        stack=("${stack[@]:0:${#stack[@]}-1}")

        local -a children
        mapfile -t children < <(pgrep -P "$current" 2>/dev/null || true)

        local child
        for child in "${children[@]}"; do
            [[ -z "$child" ]] && continue
            result+=("$child")
            stack+=("$child")
        done
    done

    printf '%s\n' "${result[@]}"
}

is_running() {
    local pid="$1"
    local state

    state="$(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ')" || return 1
    [[ -z "$state" ]] && return 1
    [[ "$state" == Z* ]] && return 1
    return 0
}

find_descendant_matching() {
    local root="$1"
    local pattern="$2"
    local pid

    while IFS= read -r pid; do
        [[ "$pid" == "$root" ]] && continue
        if tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -qE "$pattern"; then
            echo "$pid"
            return 0
        fi
    done < <(descendants_of "$root")

    return 1
}

snapshot_tree() {
    local root="$1"
    echo "  --- Process tree for $root ---" | tee -a "$TEST_LOG"
    local pid
    while IFS= read -r pid; do
        ps -o pid=,ppid=,stat=,cmd= -p "$pid" 2>/dev/null | tee -a "$TEST_LOG" || true
    done < <(descendants_of "$root")
}

# ============================================================
# Monitor lifecycle helpers
# ============================================================

start_monitor() {
    "$MONITOR" >/dev/null 2>&1 &
    MONITOR_PID=$!
    sleep "$STARTUP_WAIT"

    if ! is_running "$MONITOR_PID"; then
        fail "Monitor did not start (PID $MONITOR_PID)"
        MONITOR_PID=""
        return 1
    fi

    info "Monitor started with PID $MONITOR_PID"
    return 0
}

stop_monitor() {
    [[ -z "${MONITOR_PID:-}" ]] && return

    if is_running "$MONITOR_PID"; then
        kill -TERM "$MONITOR_PID" 2>/dev/null || true
        sleep 3
        if is_running "$MONITOR_PID"; then
            kill -KILL "$MONITOR_PID" 2>/dev/null || true
            sleep 1
        fi
    fi

    MONITOR_PID=""
}

supervisor_alerted() {
    local name="$1"
    grep -q "MONITOR STOPPED: $name monitor" "$LOGFILE" 2>/dev/null
}

# ============================================================
# Test 1: Kill journalctl --follow (scoped)
# ============================================================

test_kill_journalctl() {
    section "Test 1: Kill journalctl --follow (this monitor only)"

    start_monitor || return

    local jc_pid
    jc_pid="$(find_descendant_matching "$MONITOR_PID" 'journalctl.*--follow' || true)"

    if [[ -z "$jc_pid" ]]; then
        fail "No journalctl --follow descendant found for monitor $MONITOR_PID"
        snapshot_tree "$MONITOR_PID"
        stop_monitor
        return
    fi

    info "journalctl --follow PID (descendant of $MONITOR_PID): $jc_pid"
    kill "$jc_pid" 2>/dev/null || true

    info "Waiting ${SUPERVISOR_WAIT}s..."
    sleep "$SUPERVISOR_WAIT"

    if supervisor_alerted "journal"; then
        pass "Supervisor detected journal monitor death"
    else
        fail "Supervisor did NOT detect journal monitor death"
        snapshot_tree "$MONITOR_PID"
    fi

    stop_monitor
    sleep 2
}

# ============================================================
# Test 2: Kill sudo tail (scoped)
# ============================================================

test_kill_tail() {
    section "Test 2: Kill sudo tail (audit monitor, this monitor only)"

    start_monitor || return

    local tail_pid
    tail_pid="$(find_descendant_matching "$MONITOR_PID" 'tail.*audit\.log' || true)"

    if [[ -z "$tail_pid" ]]; then
        fail "No audit tail descendant found — audit monitor is not running"
        info "Likely cause: no passwordless sudo, or gate failed"
        snapshot_tree "$MONITOR_PID"
        stop_monitor
        return
    fi

    info "tail PID (descendant of $MONITOR_PID): $tail_pid"
    kill "$tail_pid" 2>/dev/null || true

    info "Waiting ${SUPERVISOR_WAIT}s..."
    sleep "$SUPERVISOR_WAIT"

    if supervisor_alerted "audit"; then
        pass "Supervisor detected audit monitor death"
    else
        fail "Supervisor did NOT detect audit monitor death"
        snapshot_tree "$MONITOR_PID"
    fi

    stop_monitor
    sleep 2
}

# ============================================================
# Test 3: Kill udevadm monitor (scoped)
# ============================================================

test_kill_udevadm() {
    section "Test 3: Kill udevadm monitor (this monitor only)"

    start_monitor || return

    local udev_pid
    udev_pid="$(find_descendant_matching "$MONITOR_PID" 'udevadm monitor' || true)"

    if [[ -z "$udev_pid" ]]; then
        fail "No udevadm monitor descendant found"
        snapshot_tree "$MONITOR_PID"
        stop_monitor
        return
    fi

    info "udevadm monitor PID (descendant of $MONITOR_PID): $udev_pid"
    kill "$udev_pid" 2>/dev/null || true

    info "Waiting ${SUPERVISOR_WAIT}s..."
    sleep "$SUPERVISOR_WAIT"

    if supervisor_alerted "usb"; then
        pass "Supervisor detected USB monitor death"
    else
        fail "Supervisor did NOT detect USB monitor death"
        snapshot_tree "$MONITOR_PID"
    fi

    stop_monitor
    sleep 2
}

# ============================================================
# Test 4: Restart journald and verify continued operation
# ============================================================

test_restart_journald() {
    section "Test 4: Restart systemd-journald and verify monitoring continues"

    start_monitor || return

    local jc_pid_before
    jc_pid_before="$(find_descendant_matching "$MONITOR_PID" 'journalctl.*--follow' || true)"

    if [[ -z "$jc_pid_before" ]]; then
        fail "No journalctl descendant before restart"
        stop_monitor
        return
    fi

    info "Journal monitor PID before restart: $jc_pid_before"

    local marker="SECMON_TEST_PERMISSION_DENIED_$(date +%s)"

    info "Restarting systemd-journald..."
    if ! sudo -n systemctl restart systemd-journald 2>/dev/null; then
        fail "sudo -n systemctl restart systemd-journald failed"
        stop_monitor
        return
    fi

    info "Waiting ${SUPERVISOR_WAIT}s for supervisor iteration..."
    sleep "$SUPERVISOR_WAIT"

    local jc_pid_after
    jc_pid_after="$(find_descendant_matching "$MONITOR_PID" 'journalctl.*--follow' || true)"

    if [[ -z "$jc_pid_after" ]]; then
        info "Journal monitor no longer running — supervisor should have alerted"
        if supervisor_alerted "journal"; then
            pass "Journal monitor exited; supervisor correctly alerted"
        else
            fail "Journal monitor exited; supervisor did NOT alert"
        fi
        stop_monitor
        return
    fi

    if [[ "$jc_pid_after" != "$jc_pid_before" ]]; then
        info "Journal monitor restarted (PID $jc_pid_before -> $jc_pid_after)"
    else
        info "Journal monitor survived journald restart (same PID)"
    fi

    info "Generating test event matching the monitor's regex..."
    logger -p err "SECMON_TEST: permission denied $marker" || true
    sleep 6

    if grep -q "$marker" "$LOGFILE"; then
        pass "Journal monitor detected a post-restart event"
    else
        fail "Journal monitor did NOT detect a post-restart event (silent blindness)"
    fi

    stop_monitor
    sleep 2
}

# ============================================================
# Test 5: Clean shutdown
# ============================================================

test_clean_shutdown() {
    section "Test 5: Clean shutdown (SIGTERM)"

    start_monitor || return

    local mp="$MONITOR_PID"
    local descendants_before
    mapfile -t descendants_before < <(descendants_of "$mp")

    info "Monitor PID: $mp"
    info "Descendants before SIGTERM: ${#descendants_before[@]}"

    info "Sending SIGTERM..."
    kill -TERM "$mp" 2>/dev/null || true
    sleep 5

    if is_running "$mp"; then
        fail "Main monitor process still alive after SIGTERM"
    else
        pass "Main monitor process exited"
    fi

    local survivors=0
    local pid
    for pid in "${descendants_before[@]}"; do
        [[ "$pid" == "$mp" ]] && continue
        if is_running "$pid"; then
            survivors=$((survivors+1))
            ps -o pid=,ppid=,stat=,cmd= -p "$pid" 2>/dev/null | tee -a "$TEST_LOG" || true
        fi
    done

    if (( survivors > 0 )); then
        fail "$survivors descendant process(es) survived cleanup"
    else
        pass "All descendant processes reaped"
    fi

    if grep -q "Security monitor stopped." "$LOGFILE"; then
        pass "Log shows clean shutdown message"
    else
        fail "Log missing 'Security monitor stopped.'"
    fi

    info "Starting a second instance to verify lock is free..."
    "$MONITOR" >/dev/null 2>&1 &
    local new_pid=$!
    sleep "$STARTUP_WAIT"

    if is_running "$new_pid"; then
        pass "New instance started (lock released)"
        kill -TERM "$new_pid" 2>/dev/null || true
        sleep 3
        if is_running "$new_pid"; then
            kill -KILL "$new_pid" 2>/dev/null || true
        fi
    else
        fail "New instance could not start — lock may still be held"
    fi

    MONITOR_PID=""
}

# ============================================================
# Main test runner
# ============================================================

main() {
    echo "============================================================"
    echo "  Lifecycle Test Suite for security_check.sh v2.2"
    echo "  Log: $TEST_LOG"
    echo "============================================================"
    echo

    if pgrep -f "security_check.sh" >/dev/null 2>&1; then
        echo "ERROR: A monitor instance is already running." >&2
        echo "Stop it manually before running this test suite:" >&2
        echo "  pkill -TERM -f 'security_check.sh'" >&2
        exit 1
    fi

    test_kill_journalctl
    test_kill_tail
    test_kill_udevadm
    test_restart_journald
    test_clean_shutdown

    section "Summary"
    echo "  Passed: $PASS"
    echo "  Failed: $FAIL"
    echo "  Full log: $TEST_LOG"
    echo

    if (( FAIL == 0 )); then
        echo -e "${GREEN}All tests passed. v2.2 lifecycle behavior is sound.${NC}"
        return 0
    else
        echo -e "${RED}$FAIL test(s) failed. Review the log and process snapshots.${NC}"
        return 1
    fi
}

main "$@"
