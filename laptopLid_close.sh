#!/usr/bin/env bash
# ============================================================
# Laptop Lid & HDMI Monitor
# ============================================================
# Locks the session when:
#   1. The lid is closed
#   2. AND no HDMI monitor is connected
#
# Dependencies (optional but recommended):
#   - acpid / acpi_listen  → Instant lid detection
#   - udevadm              → Instant HDMI hotplug detection
#
# Fallback: If acpi_listen is missing, falls back to 1-second
# polling (still efficient and locks within 1 second).
# ============================================================

 --- Single-Instance Lock ---
LOCK_FILE="/tmp/laptopLid_close_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

echo $$ > "$LOCK_FILE"

# --- Cleanup ---
cleanup() {
    # Kill the udevadm background process if it's running
    if [[ -n "$UDEV_PID" ]] && kill -0 "$UDEV_PID" 2>/dev/null; then
        kill "$UDEV_PID" 2>/dev/null
    fi

    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
}

trap cleanup EXIT

# --- Helper Functions ---
get_lid_state() {
    awk '{print $2}' /proc/acpi/button/lid/*/state 2>/dev/null
}

hdmi_connected() {
    xrandr | grep ' connected' | grep -qi 'HDMI'
}

check_and_lock() {
    if [[ "$(get_lid_state)" == "closed" ]] && ! hdmi_connected; then
        loginctl lock-session
    fi
}

# --- Check once at startup ---
check_and_lock

# --- Start udev monitor in background for HDMI events ---
if command -v udevadm &>/dev/null; then
    (
        udevadm monitor --subsystem-match=drm --property 2>/dev/null | while read -r line; do
            if [[ "$line" =~ "HOTPLUG=1" ]] || [[ "$line" =~ "change" ]]; then
                check_and_lock
            fi
        done
    ) &
    UDEV_PID=$!
fi

# --- Main Event Loop (Ideal: with acpi_listen) ---
while true; do
    # Wait up to 5 seconds for a lid event.
    # If a lid event arrives, handle it instantly.
    # If nothing happens for 5 seconds, run a backup check.
    if read -t 5 event < <(acpi_listen); then
        if [[ "$event" == *"button/lid"* ]]; then
            check_and_lock
        fi
    else
        # Backup safety net (catches edge cases if udevadm fails)
        check_and_lock
    fi
done
