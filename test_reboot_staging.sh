#!/usr/bin/env bash
# Usage: test_reboot_staging.sh [normal|restage|fail|noboot|dryrun]
# Needs auto_system_update_nobara.sh in the same directory (or SCRIPT=/path).
# Run with no args for the main scenario; see below for all of them.
# Notifications are FAKED (logged to a file) unless REAL_NOTIFY=1 is set, in
# which case they also appear on your desktop (dismiss the critical one).
set -u
SCEN="${1:-normal}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${SCRIPT:-$HERE/auto_system_update_nobara.sh}"
[[ -r "$SCRIPT" ]] || { echo "Script under test not found: $SCRIPT (set SCRIPT=/path/to/script)"; exit 98; }
T=$(mktemp -d); export HOME="$T/home"; SHIM="$T/shim"; mkdir -p "$HOME" "$SHIM"
export T SCEN
if [[ "${REAL_NOTIFY:-0}" == "1" ]]; then
  REAL_NOTIFY_BIN="${REAL_NOTIFY_BIN:-$(command -v notify-send || true)}"
  if [[ -z "$REAL_NOTIFY_BIN" ]]; then echo "REAL_NOTIFY=1 but notify-send not found; logging only"; fi
  export REAL_NOTIFY_BIN
fi
export BOOT_ID_FILE="$T/boot_id"; echo "boot-AAAA" > "$BOOT_ID_FILE"
[[ "$SCEN" == "noboot" ]] && export BOOT_ID_FILE="$T/does-not-exist"
touch "$T/dnf_pending"
: > "$T/notify.log"; : > "$T/nscount"

# ---- shims -------------------------------------------------------------
cat > "$SHIM/sudo" <<'S'
#!/usr/bin/env bash
[[ "$1" == "-n" ]] && shift
c=$(basename "$1"); shift
case "$c" in
  nobara-sync) exec "$(dirname "$0")/nobara-sync" "$@" ;;
  dnf)         exec "$(dirname "$0")/dnf" "$@" ;;
  flatpak)     exec "$(dirname "$0")/flatpak" "$@" ;;
  ls)          exec /bin/ls "$@" ;;
  true)        exit 0 ;;
  *)           exit 0 ;;
esac
S
cat > "$SHIM/nobara-sync" <<'S'
#!/usr/bin/env bash
echo x >> "$T/nscount"
echo "INFO Installation requires a restart:"
echo 'System update will install on the next restart.'
echo 'NOBARA_UPDATE_RESULT {"status": "scheduled", "message": "System update will install on the next restart.", "reboot_required": true, "automatic_recovery": true}'
[[ "$SCEN" == "fail" ]] && exit 1
exit 0
S
cat > "$SHIM/dnf" <<'S'
#!/usr/bin/env bash
case "$1" in
  check-update)
    if [[ -e "$T/dnf_pending" ]]; then
      echo; echo "kernel-cachyos.x86_64   7.3.0-4.cachyos1.fc44   copr:x"
      echo "vivaldi-stable.x86_64   8.2.4133.94-1           vivaldi"; exit 100
    fi; exit 0 ;;
  history) echo "ID Command"; echo "549 upgrade"; exit 0 ;;
  *) exit 0 ;;
esac
S
cp "$SHIM/dnf" "$SHIM/dnf5"
cat > "$SHIM/flatpak" <<'S'
#!/usr/bin/env bash
case "$1" in update) echo "Nothing to update." ;; esac; exit 0
S
cat > "$SHIM/curl" <<'S'
#!/usr/bin/env bash
exit 0
S
cat > "$SHIM/notify-send" <<'S'
#!/usr/bin/env bash
# args: -u urgency -t ms summary body
printf '%s | %s\n' "$2" "$(printf '%s ' "${@:5}" | tr '\n' ' ')" >> "$T/notify.log"
# REAL_NOTIFY=1: also show it on the desktop (RESTART REQUIRED is critical, -t 0:
# it stays until dismissed)
[[ -n "${REAL_NOTIFY_BIN:-}" ]] && "$REAL_NOTIFY_BIN" "$@" 2>/dev/null
exit 0
S
cat > "$SHIM/rpm" <<'S'
#!/usr/bin/env bash
# Emulate: installed kernel == running kernel (update staged, not installed)
case "$1" in
  -qf) echo "kernel-cachyos-core-$(uname -r)" ;;
  -q)  echo "$2-$(uname -r)" ;;
esac; exit 0
S
cat > "$SHIM/findmnt" <<'S'
#!/usr/bin/env bash
case "$*" in *OPTIONS*) echo "rw,relatime" ;; *) echo "/" ;; esac
S
for c in journalctl systemctl ss aa-status upower; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$SHIM/$c"
done
# systemctl --failed must print nothing and succeed; is-active must succeed
# sleep: fast-forward; drives the scenario and stops the daemon
cat > "$SHIM/sleep" <<'S'
#!/usr/bin/env bash
[[ "$1" == "60" ]] && exec /bin/sleep 60            # keep-alive loop: real
LOG="$HOME/scriptlogs/nobara_update_log.txt"
runs=$(wc -l < "$T/nscount")
skips=$(grep -c 'Update already staged' "$LOG" 2>/dev/null)
if [[ $skips -ge 2 && ! -e "$T/rebooted" ]]; then       # simulate a reboot
  echo "boot-BBBB" > "$BOOT_ID_FILE"; touch "$T/rebooted"
  [[ "$SCEN" == "normal" ]] && rm -f "$T/dnf_pending"   # update applied at boot
fi
if [[ -e "$T/rebooted" ]]; then
  # run 4th cycle then stop: normal -> up-to-date cycle ; restage -> 2nd run
  c4=$(grep -c 'Advisory checks complete\|System is up to date' "$LOG" 2>/dev/null)
  if [[ "$SCEN" == "restage" && $runs -ge 2 ]] || [[ "$SCEN" == "normal" && $c4 -ge 2 ]]; then
    kill -TERM "$PPID"; exit 0
  fi
fi
[[ "$SCEN" =~ ^(fail|noboot|dryrun)$ ]] && { kill -TERM "$PPID"; exit 0; }
[[ -n "${CONTROL:-}" && $runs -ge 3 ]] && { kill -TERM "$PPID"; exit 0; }
# Non-zero exit makes smart_sleep's "sleep || break" end the wait immediately,
# instead of looping ~720 times per simulated hour.
exit 1
S
chmod +x "$SHIM"/*

# ---- test copy: only PATH line differs; main is invoked normally --------
sed "s#^export PATH=\"#export PATH=\"$SHIM:#" "$SCRIPT" > "$T/script.sh"
grep -q "$SHIM" "$T/script.sh" || { echo "PATH patch failed"; exit 99; }

timeout "${TEST_TIMEOUT:-180}" bash "$T/script.sh" ${ARGS:-} > "$T/stdout.txt" 2>&1
rc=$?
[[ $rc -eq 124 ]] && echo "!! harness timed out after ${TEST_TIMEOUT:-180}s (machine very slow?); raise TEST_TIMEOUT"
LOG="$HOME/scriptlogs/nobara_update_log.txt"
ST="$HOME/.auto_update_state"

pass=0; fail=0
check() { if eval "$2"; then echo "  PASS: $1"; pass=$((pass+1)); else echo "  FAIL: $1"; fail=$((fail+1)); fi; }
runs=$(wc -l < "$T/nscount")
skips=$(grep -c 'Update already staged' "$LOG")
restart_notes=$(grep -c 'RESTART REQUIRED' "$T/notify.log")
echo "== scenario: $SCEN  (script exit=$rc, nobara-sync runs=$runs, skips=$skips, restart notifications=$restart_notes)"
if [[ "$SCEN" =~ ^(fail|noboot|dryrun)$ ]]; then
  check "no staged marker written" '[[ ! -e "$ST/reboot_staged" ]]'
  check "no RESTART notification" '[[ $restart_notes -eq 0 ]]'
  [[ "$SCEN" == "fail"   ]] && check "failure alert logged" 'grep -q "ALERT: System update failed" "$LOG"'
  [[ "$SCEN" == "noboot" ]] && check "warning logged for unreadable boot id" 'grep -q "boot ID unreadable" "$LOG"'
  [[ "$SCEN" == "dryrun" ]] && check "dry-run: nobara-sync never ran" '[[ $runs -eq 0 ]]'
  echo "  -> $pass passed, $fail failed"; [[ $fail -gt 0 ]] && tail -30 "$LOG"; exit $fail
fi
check "daemon stopped by SIGTERM (exit 143), not a crash/timeout" '[[ $rc -eq 143 ]]'
check "cycle 1: staged update logged" 'grep -q "nobara-sync staged an update" "$LOG"'
check "cycle 1: critical RESTART REQUIRED notification sent" 'grep -q "^critical | .*RESTART REQUIRED" "$T/notify.log"'
check "reason text says staged offline" 'grep -q "Update staged offline" "$T/notify.log"'
check "cycles 2-3: skipped (no re-staging) while staged" '[[ $skips -ge 2 ]]'
check "no duplicate notification while staged (same boot)" '[[ $(grep -c RESTART "$T/notify.log") -ge 1 ]]'
if [[ "$SCEN" == "normal" ]]; then
  check "nobara-sync ran exactly once" '[[ $runs -eq 1 ]]'
  check "exactly one RESTART notification" '[[ $restart_notes -eq 1 ]]'
  check "after reboot: stale marker removed" '[[ ! -e "$ST/reboot_staged" ]]'
  check "after reboot: reboot_notified cleared to false" '[[ "$(tr -d "[:space:]" < "$ST/reboot_notified")" == "false" ]]'
  check "log shows notification cleared" 'grep -q "Cleared reboot notification" "$LOG"'
else
  check "restage after reboot: nobara-sync ran twice" '[[ $runs -eq 2 ]]'
  check "restage after reboot: second RESTART notification sent" '[[ $restart_notes -eq 2 ]]'
  check "marker now holds the new boot id" '[[ "$(tr -d "[:space:]" < "$ST/reboot_staged")" == "boot-BBBB" ]]'
fi
echo "  -> $pass passed, $fail failed"
[[ $fail -gt 0 ]] && { echo "--- log tail ---"; tail -40 "$LOG"; echo "--- stdout ---"; tail -15 "$T/stdout.txt"; }
rm -rf "$T"
exit $fail
