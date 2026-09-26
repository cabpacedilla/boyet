#!/usr/bin/env bash
# ============================================================
# Focused test for journal and login monitor behavior
# in security_check.sh
# ============================================================

set -o nounset
set -o pipefail

readonly MONITOR="$HOME/Documents/bin/security_check.sh"
readonly LOGFILE="$HOME/scriptlogs/fedora-sec-proactive.log"
readonly TEST_LOG="$HOME/scriptlogs/journal-monitor-test.log"

readonly STARTUP_WAIT=10
readonly OBSERVATION_TIME=30

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()     { echo -e "${BLUE}[TEST]${NC} $*" | tee -a "$TEST_LOG"; }
pass()    { echo -e "${GREEN}[PASS]${NC} $*" | tee -a "$TEST_LOG"; }
fail()    { echo -e "${RED}[FAIL]${NC} $*" | tee -a "$TEST_LOG"; }
info()    { echo -e "${YELLOW}[INFO]${NC} $*" | tee -a "$TEST_LOG"; }
section() { echo; echo "============================================================" | tee -a "$TEST_LOG"; echo "  $*" | tee -a "$TEST_LOG"; echo "============================================================" | tee -a "$TEST_LOG"; }

if [[ ! -x "$MONITOR" ]]; then
    echo "Monitor not found: $MONITOR" >&2
    exit 1
fi

mkdir -p "$(dirname "$TEST_LOG")"
: > "$TEST_LOG"

MONITOR_PID=""

# ============================================================
# Cleanup
# ============================================================

cleanup_all() {
    pkill -KILL -f "security_check.sh" 2>/dev/null || true
    sleep 2
    sudo -n pkill -f "tail -n0 -F /var/log/audit/audit.log" 2>/dev/null || true
    pkill -f "journalctl --follow" 2>/dev/null || true
    sudo -n pkill -f "udevadm monitor --subsystem-match=usb" 2>/dev/null || true
    sleep 2
}

# ============================================================
# Start monitor with debug enabled
# ============================================================

start_monitor_debug() {
    info "Cleaning up any running instances first..."
    cleanup_all

    info "Starting monitor with DEBUG_MONITORS=1"
    DEBUG_MONITORS=1 nohup "$MONITOR" </dev/null >/dev/null 2>&1 &
    MONITOR_PID=$!
    info "Monitor launched with PID $MONITOR_PID"
    sleep "$STARTUP_WAIT"

    if ! kill -0 "$MONITOR_PID" 2>/dev/null; then
        fail "Monitor died during startup"
        return 1
    fi
    pass "Monitor is running"
    return 0
}

# ============================================================
# Count processes
# ============================================================

count_processes() {
    local pattern="$1"
    pgrep -f "$pattern" 2>/dev/null | wc -l
}

# ============================================================
# Print process tree
# ============================================================

print_tree() {
    section "Process Tree"
    local mp="$MONITOR_PID"
    ps -ef --forest | grep -A 30 " ${mp} " | head -35 | tee -a "$TEST_LOG"
}

# ============================================================
# Print debug lines
# ============================================================

print_debug() {
    section "Debug Log (journal + login)"
    grep -E '\[DEBUG\] (journal|login)' "$LOGFILE" | tail -30 | tee -a "$TEST_LOG"
}

# ============================================================
# Test 1: Basic startup — all monitors present
# ============================================================

test_startup() {
    section "Test 1: Startup — all monitors present"

    start_monitor_debug || return

    local main audit journal login usb services
    main=$(count_processes "security_check.sh")
    audit=$(count_processes "tail.*audit.log")
    journal=$(count_processes "journalctl.*follow.*err..emerg")
    login=$(count_processes "journalctl.*follow.*sshd")
    usb=$(count_processes "udevadm.*subsystem-match=usb")

    info "Main:     $main"
    info "Audit:    $audit (expect 2: sudo tail + tail)"
    info "Journal:  $journal (expect 1)"
    info "Login:    $login (expect 1)"
    info "USB:      $usb (expect 1)"

    if (( main >= 1 )); then
        pass "Main script running"
    else
        fail "Main script NOT running"
    fi

    if (( audit >= 2 )); then
        pass "Audit monitor running (both tail processes)"
    else
        fail "Audit monitor missing"
    fi

    if (( journal >= 1 )); then
        pass "Journal monitor running"
    else
        fail "Journal monitor MISSING"
    fi

    if (( login >= 1 )); then
        pass "Login monitor running"
    else
        fail "Login monitor MISSING"
    fi

    if (( usb >= 1 )); then
        pass "USB monitor running"
    else
        fail "USB monitor missing"
    fi

    print_tree
}

# ============================================================
# Test 2: Observe for 30 seconds
# ============================================================

test_stability() {
    section "Test 2: Stability over ${OBSERVATION_TIME}s"

    if ! kill -0 "$MONITOR_PID" 2>/dev/null; then
        fail "Monitor already dead before stability test"
        return
    fi

    info "Waiting ${OBSERVATION_TIME}s..."
    sleep "$OBSERVATION_TIME"

    local main journal login
    main=$(count_processes "security_check.sh")
    journal=$(count_processes "journalctl.*follow.*err..emerg")
    login=$(count_processes "journalctl.*follow.*sshd")

    info "After ${OBSERVATION_TIME}s:"
    info "  Main:    $main"
    info "  Journal: $journal"
    info "  Login:   $login"

    if (( main >= 1 )); then
        pass "Main still running"
    else
        fail "Main died"
    fi

    if (( journal >= 1 )); then
        pass "Journal monitor still alive"
    else
        fail "Journal monitor died"
    fi

    if (( login >= 1 )); then
        pass "Login monitor still alive"
    else
        fail "Login monitor died"
    fi
}

# ============================================================
# Test 3: Analyze debug log
# ============================================================

test_debug_analysis() {
    section "Test 3: Debug log analysis"

    print_debug

    # Check whether journal monitor entered its pipeline
    if grep -q '\[DEBUG\] journal: entering journalctl pipeline' "$LOGFILE"; then
        pass "Journal monitor reached 'entering pipeline'"
    else
        fail "Journal monitor NEVER reached 'entering pipeline'"
    fi

    if grep -q '\[DEBUG\] login: entering journalctl pipeline' "$LOGFILE"; then
        pass "Login monitor reached 'entering pipeline'"
    else
        fail "Login monitor NEVER reached 'entering pipeline'"
    fi

    # Check whether pipeline exited
    if grep -q '\[DEBUG\] journal: journalctl pipeline exited' "$LOGFILE"; then
        info "Journal monitor's pipeline exited — that means journalctl returned"
    fi

    if grep -q '\[DEBUG\] login: journalctl pipeline exited' "$LOGFILE"; then
        info "Login monitor's pipeline exited — that means journalctl returned"
    fi
}

# ============================================================
# Test 4: Clean shutdown
# ============================================================

test_shutdown() {
    section "Test 4: Clean shutdown"

    if ! kill -0 "$MONITOR_PID" 2>/dev/null; then
        fail "Monitor already dead"
        return
    fi

    info "Sending SIGTERM to main monitor..."
    kill -TERM "$MONITOR_PID" 2>/dev/null || true
    sleep 5

    if kill -0 "$MONITOR_PID" 2>/dev/null; then
        fail "Monitor still alive after SIGTERM"
    else
        pass "Monitor exited cleanly"
    fi

    local remaining
    remaining=$(pgrep -f "security_check.sh" 2>/dev/null | wc -l)
    if (( remaining == 0 )); then
        pass "No lingering main processes"
    else
        fail "$remaining main process(es) still running"
    fi

    remaining=$(pgrep -f "journalctl.*follow" 2>/dev/null | wc -l)
    if (( remaining == 0 )); then
        pass "No lingering journalctl processes"
    else
        fail "$remaining journalctl process(es) still running"
    fi
}

# ============================================================
# Main
# ============================================================

main() {
    echo "============================================================"
    echo "  Focused test for journal/login monitors (v2.5)"
    echo "  Test log: $TEST_LOG"
    echo "============================================================"
    echo

    test_startup
    test_stability
    test_debug_analysis
    test_shutdown

    section "Summary"
    echo "  Test log:  $TEST_LOG" | tee -a "$TEST_LOG"
    echo "  Main log:  $LOGFILE" | tee -a "$TEST_LOG"
    echo
    echo "  Review $TEST_LOG for full details." | tee -a "$TEST_LOG"
    echo "  Review the [DEBUG] lines in $LOGFILE" | tee -a "$TEST_LOG"
    echo "  to see exactly where the journal/login monitors" | tee -a "$TEST_LOG"
    echo "  enter and exit their pipelines." | tee -a "$TEST_LOG"
}

main "$@"
