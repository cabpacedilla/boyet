#!/usr/bin/env bash
# ============================================================
# Installer for random_wallpaper.sh systemd services
#
# Version: 2.0 — Production Baseline (Frozen)
#
# Architecture:
#   - User service:  wallpaper-changer.service
#   - Resume hook:   /etc/systemd/system-sleep/random-wallpaper-resume
#   - Targets:       the installing user only
#   - Privilege:     runuser + env (not sudo -u)
# ============================================================
set -euo pipefail

# ============================================================
# ROOT GUARD — MUST RUN AS NORMAL USER
# ============================================================
if [ "$EUID" -eq 0 ]; then
    echo "[x] Do not run this installer with sudo." >&2
    echo "[x] Run it as your normal user; the installer will request sudo when needed." >&2
    exit 1
fi

# ============================================================
# CONFIG
# ============================================================
SCRIPT_PATH="$HOME/Documents/bin/random_wallpaper.sh"
USER_SERVICE_DIR="$HOME/.config/systemd/user"
USER_SERVICE="$USER_SERVICE_DIR/wallpaper-changer.service"

# Distinctive, installer-owned filename (not generic)
SLEEP_HOOK="/etc/systemd/system-sleep/random-wallpaper-resume"

LOG_DIR="$HOME/scriptlogs"
LOCK_DIR="$HOME/.cache"

USERNAME="$(id -un)"
USER_UID="$(id -u)"

# Legacy artifacts from v1 installer
LEGACY_TEMPLATE="/etc/systemd/system/restart-wallpaper@.service"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[x]${NC} $*" >&2; }
info() { echo -e "${BLUE}[i]${NC} $*"; }

# ============================================================
# ARG PARSING
# ============================================================
UNINSTALL=false
SKIP_VALIDATION=false

for arg in "$@"; do
    case "$arg" in
        --uninstall|-u)    UNINSTALL=true ;;
        --skip-validation) SKIP_VALIDATION=true ;;
        --skip-verify)     SKIP_VALIDATION=true ;;  # backward-compat alias
        --help|-h)
            cat <<EOF
Usage: $0 [OPTIONS]

Options:
  -u, --uninstall         Remove the user service and sleep hook
      --skip-validation   Skip generated-file validation
  -h, --help              Show this help
EOF
            exit 0
            ;;
    esac
done

# ============================================================
# UNINSTALL PATH
# ============================================================
if [ "$UNINSTALL" = true ]; then
    log "Uninstalling wallpaper services..."

    systemctl --user disable --now wallpaper-changer.service 2>/dev/null || true
    rm -f "$USER_SERVICE"

    if [ -f "$SLEEP_HOOK" ]; then
        sudo rm -f "$SLEEP_HOOK"
        log "Removed sleep hook: $SLEEP_HOOK"
    fi

    # Legacy v1 cleanup
    if [ -f "$LEGACY_TEMPLATE" ]; then
        sudo systemctl disable "restart-wallpaper@$USERNAME.service" 2>/dev/null || true
        sudo rm -f "$LEGACY_TEMPLATE"
        log "Removed legacy restart-wallpaper@.service"
    fi

    systemctl --user daemon-reload
    sudo systemctl daemon-reload

    log "Uninstall complete."
    info "Logs and history left in: $LOG_DIR"
    exit 0
fi

# ============================================================
# 1. SANITY CHECKS
# ============================================================
log "Checking prerequisites..."

if [ ! -f "$SCRIPT_PATH" ]; then
    err "Script not found at $SCRIPT_PATH"
    exit 1
fi

if [ ! -x "$SCRIPT_PATH" ]; then
    warn "$SCRIPT_PATH is not executable — fixing..."
    chmod +x "$SCRIPT_PATH"
fi

# Installer prerequisites (must be present)
for cmd in systemctl runuser logger sudo; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        err "Required command not found: $cmd"
        exit 1
    fi
done

# Runtime dependencies (informational)
info "Runtime dependencies for the wallpaper script:"
for cmd in flock plasma-apply-wallpaperimage deviousq variety; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "    ✓ $cmd"
    else
        warn "  $cmd not found — the script may fall back or fail at runtime"
    fi
done

# ============================================================
# 2. CREATE DIRECTORIES
# ============================================================
log "Creating directories..."
mkdir -p "$USER_SERVICE_DIR" "$LOG_DIR" "$LOCK_DIR"

# ============================================================
# 3. IDEMPOTENCY — CLEAN UP LEGACY V1 ARTIFACTS
# ============================================================
if [ -f "$LEGACY_TEMPLATE" ]; then
    warn "Found legacy restart-wallpaper@.service — removing"
    sudo systemctl disable "restart-wallpaper@$USERNAME.service" 2>/dev/null || true
    sudo rm -f "$LEGACY_TEMPLATE"
fi

# ============================================================
# 4. WRITE USER SERVICE
# ============================================================
log "Writing user service: $USER_SERVICE"
cat > "$USER_SERVICE" <<EOF
[Unit]
Description=Random Wallpaper Script
After=graphical-session.target

[Service]
Type=simple
ExecStart=%h/Documents/bin/random_wallpaper.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

# ============================================================
# 5. WRITE SLEEP HOOK
# ============================================================
log "Writing sleep hook: $SLEEP_HOOK"

if [ -f "$SLEEP_HOOK" ]; then
    info "Updating existing wallpaper sleep hook"
fi

# Bake in the installing user's identity
sudo tee "$SLEEP_HOOK" > /dev/null <<HOOK_EOF
#!/usr/bin/env bash
# ============================================================
# /etc/systemd/system-sleep/random-wallpaper-resume
#
# Installed by: install-wallpaper-service.sh
# Target user:  $USERNAME (uid $USER_UID)
#
# Restarts the user's wallpaper-changer.service after resume.
# ============================================================

set -u

TARGET_USER='$USERNAME'
TARGET_UID='$USER_UID'

# Only act on resume
if [ "\${1:-}" != "post" ]; then
    exit 0
fi

logger -t wallpaper-resume \\
    "Resume detected (type=\${2:-unknown}), restarting wallpaper service for \$TARGET_USER"

# Give the network stack and DBus a moment to settle
sleep 3

runtime_dir="/run/user/\$TARGET_UID"
bus_addr="unix:path=\$runtime_dir/bus"

if [ ! -S "\$runtime_dir/bus" ]; then
    logger -t wallpaper-resume \\
        "No DBus socket for \$TARGET_USER (\$runtime_dir); skipping"
    exit 0
fi

ready=false

for ((attempt=1; attempt<=10; attempt++)); do
    if runuser -u "\$TARGET_USER" -- env \\
        XDG_RUNTIME_DIR="\$runtime_dir" \\
        DBUS_SESSION_BUS_ADDRESS="\$bus_addr" \\
        systemctl --user show-environment >/dev/null 2>&1
    then
        ready=true
        break
    fi
    sleep 1
done

if [ "\$ready" != true ]; then
    logger -t wallpaper-resume \\
        "User manager for \$TARGET_USER not ready after 10s"
    exit 0
fi

if runuser -u "\$TARGET_USER" -- env \\
    XDG_RUNTIME_DIR="\$runtime_dir" \\
    DBUS_SESSION_BUS_ADDRESS="\$bus_addr" \\
    systemctl --user restart wallpaper-changer.service
then
    logger -t wallpaper-resume \\
        "Restarted wallpaper-changer.service for \$TARGET_USER"
else
    logger -t wallpaper-resume \\
        "Failed to restart wallpaper-changer.service for \$TARGET_USER"
fi

exit 0
HOOK_EOF

sudo chmod 755 "$SLEEP_HOOK"

# ============================================================
# 6. VALIDATE GENERATED FILES
# ============================================================
if [ "$SKIP_VALIDATION" != true ]; then
    log "Validating generated files..."

    if command -v systemd-analyze >/dev/null 2>&1; then
        if systemd-analyze verify "$USER_SERVICE" 2>/dev/null; then
            log "User service is syntactically valid"
        else
            err "Generated user service failed validation"
            exit 1
        fi
    else
        warn "systemd-analyze not available — skipping user unit validation"
    fi

    if bash -n "$SLEEP_HOOK" 2>/dev/null; then
        log "Sleep hook is syntactically valid"
    else
        err "Sleep hook has a syntax error"
        exit 1
    fi
else
    warn "Skipping validation (--skip-validation)"
fi

# ============================================================
# 7. RELOAD SYSTEMD
# ============================================================
log "Reloading systemd daemons..."
sudo systemctl daemon-reload
systemctl --user daemon-reload

# ============================================================
# 8. ENABLE + START USER SERVICE
# ============================================================
log "Enabling and starting user service..."
systemctl --user enable --now wallpaper-changer.service

# ============================================================
# 9. STATUS SUMMARY
# ============================================================
echo
log "Installation complete."
echo
echo "  Script:          $SCRIPT_PATH"
echo "  User service:    $USER_SERVICE"
echo "  Sleep hook:      $SLEEP_HOOK"
echo "  Log file:        $LOG_DIR/wallpaper.log"
echo "  Lock file:       $LOCK_DIR/random_wallpaper.lock"
echo
echo "Useful commands:"
echo "  systemctl --user status wallpaper-changer.service"
echo "  systemctl --user restart wallpaper-changer.service"
echo "  journalctl --user -u wallpaper-changer.service -f"
echo "  tail -f $LOG_DIR/wallpaper.log"
echo "  sudo journalctl -t wallpaper-resume -f"
echo
echo "Test the resume hook:"
echo "  systemctl suspend"
echo
echo "Uninstall:"
echo "  $0 --uninstall"
echo
