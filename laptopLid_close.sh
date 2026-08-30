#!/usr/bin/env bash
# ============================================================
# Locks session when lid closed AND no HDMI connected
# 
# Dependencies:  
#   - acpi_listen (from acpid) – for instant lid events.
#     Install: sudo dnf install acpid   (Fedora/Nobara)
#              sudo apt install acpid   (Debian/Ubuntu)
# ============================================================

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
set -o pipefail

if [[ $EUID -eq 0 ]]; then
    echo "ERROR: Do not run this script as root." >&2
    exit 1
fi

# --- Secure lock ---
if [[ -z "${XDG_RUNTIME_DIR:-}" || ! -d "$XDG_RUNTIME_DIR" ]]; then
    echo "ERROR: XDG_RUNTIME_DIR unavailable." >&2
    exit 1
fi
LOCK_FILE="$XDG_RUNTIME_DIR/laptopLid_close.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    exit 1
fi
printf '%s\n' "$$" >&9

cleanup() {
    kill "$UDEV_PID" 2>/dev/null || true
    kill "$ACPID_PID" 2>/dev/null || true
    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
}
trap cleanup EXIT

# --- HDMI detection (prefer kscreen-doctor, fallback xrandr) ---
hdmi_connected() {
    if command -v kscreen-doctor &>/dev/null; then
        kscreen-doctor -o 2>/dev/null | grep -qi HDMI
    else
        xrandr 2>/dev/null | grep ' connected' | grep -qi HDMI
    fi
}

get_lid_state() {
    awk '{print $2}' /proc/acpi/button/lid/*/state 2>/dev/null
}

# --- check_and_lock with retry ---
check_and_lock() {
    local lid_state
    lid_state="$(get_lid_state)"
    if [[ "$lid_state" != "closed" ]]; then
        return
    fi

    # Retry HDMI detection up to 5 times, with 0.5s intervals
    for ((i=0; i<5; i++)); do
        if hdmi_connected; then
            # HDMI is connected – do not lock
            return
        fi
        sleep 0.5
    done

    # If we get here, HDMI is still disconnected – lock the session
    loginctl lock-session
}

# --- Initial check ---
check_and_lock

# --- Monitors ---
(
    udevadm monitor --subsystem-match=drm --property 2>/dev/null | while read -r line; do
        if [[ "$line" =~ "HOTPLUG=1" ]] || [[ "$line" =~ "change" ]]; then
            check_and_lock
        fi
    done
) &
UDEV_PID=$!

(
    acpi_listen 2>/dev/null | while read -r event; do
        if [[ "$event" == *"button/lid"* ]]; then
            check_and_lock
        fi
    done
) &
ACPID_PID=$!

# --- Periodic fallback ---
while true; do
    sleep 5
    check_and_lock
done
