#!/usr/bin/env bash
# ============================================================
# Locks session when lid closed AND no external display connected.
# Uses native systemd D-Bus and kernel DRM sysfs – works on Wayland & X11.
#
# IMPORTANT CONFIGURATION:
# To prevent systemd from suspending before this script evaluates:
# Set the following in /etc/systemd/logind.conf (or /etc/systemd/logind.conf.d/lid.conf):
#   HandleLidSwitch=ignore
#   HandleLidSwitchExternalPower=ignore
#   HandleLidSwitchDocked=ignore
# Then apply with: sudo systemctl restart systemd-logind
# ============================================================

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
set -o pipefail

# ---------- Initialisation ----------
UDEV_PID=""
BUSCTL_PID=""

if [[ $EUID -eq 0 ]]; then
    echo "ERROR: Do not run this script as root." >&2
    exit 1
fi

# ---------- Single instance lock ----------
if [[ -z "${XDG_RUNTIME_DIR:-}" || ! -d "$XDG_RUNTIME_DIR" ]]; then
    echo "ERROR: XDG_RUNTIME_DIR unavailable" >&2
    exit 1
fi
LOCK_FILE="$XDG_RUNTIME_DIR/$(basename "$0" .sh).lock"   # dynamic name
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "ERROR: Another instance is running." >&2
    exit 1
fi
printf '%s\n' "$$" >&9

cleanup() {
    # Kill the entire process group of each monitor (kills child processes too)
    [[ -n "$UDEV_PID" ]] && kill -TERM -"$UDEV_PID" 2>/dev/null || true
    [[ -n "$BUSCTL_PID" ]] && kill -TERM -"$BUSCTL_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# ---------- Lid state: D-Bus (systemd-logind) with fallback ----------
get_lid_state() {
    local state
    if command -v busctl &>/dev/null; then
        state=$(busctl --system get-property org.freedesktop.login1 \
                      /org/freedesktop/login1 \
                      org.freedesktop.login1.Manager \
                      LidClosed 2>/dev/null | awk '{print $2}')
        [[ "$state" == "true" ]] && { echo "closed"; return; }
        [[ "$state" == "false" ]] && { echo "open"; return; }
    fi

    # Fallback (older systems)
    local proc_state
    proc_state=$(awk '{print $2}' /proc/acpi/button/lid/*/state 2>/dev/null)
    [[ -n "$proc_state" ]] && echo "$proc_state" || echo "open"
}

# ---------- External display detection via DRM sysfs (Wayland-safe) ----------
hdmi_connected() {
    for status_file in /sys/class/drm/card*-*/status; do
        [[ -f "$status_file" ]] || continue
        # Skip internal panels
        [[ "$status_file" =~ eDP|LVDS ]] && continue
        if grep -q "^connected$" "$status_file" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

# ---------- Main lock logic ----------
check_and_lock() {
    local lid_state
    lid_state="$(get_lid_state)"
    [[ "$lid_state" != "closed" ]] && return

    # Retry to allow hotplug events to settle
    for ((i=0; i<5; i++)); do
        if hdmi_connected; then
            return
        fi
        sleep 0.5
    done

    # No external display – lock the session via systemd
    logger "laptopLid_close: Lid closed with no external display. Locking session."
    loginctl lock-session
}

# ---------- Initial check on script start ----------
check_and_lock

# ---------- Event monitors ----------
# 1. DRM hotplug events (external display plug/unplug)
(
    udevadm monitor --subsystem-match=drm --property 2>/dev/null | while read -r line; do
        if [[ "$line" == *"HOTPLUG=1"* ]]; then
            check_and_lock
        fi
    done
) &
UDEV_PID=$!

# 2. D-Bus lid events (native systemd signals)
(
    busctl monitor org.freedesktop.login1 2>/dev/null | while read -r line; do
        if [[ "$line" == *"LidClosed"* ]]; then
            check_and_lock
        fi
    done
) &
BUSCTL_PID=$!

# ---------- Wait for background processes ----------
wait
