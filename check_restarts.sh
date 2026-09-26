#!/usr/bin/env bash
# check_restarts.sh - Comprehensive check for what is restarting random_wallpaper

TARGET="random_wallpaper"
LOG="/tmp/restart_report_$(date +%Y%m%d_%H%M%S).txt"

# Tee everything so it prints AND saves
exec > >(tee "$LOG") 2>&1

hr() { printf '\n============================================================\n'; }
sec() { hr; echo "  $1"; hr; }

echo "Restart investigation report"
echo "Generated: $(date)"
echo "Target pattern: $TARGET"
echo "Report file: $LOG"

# ------------------------------------------------------------
sec "1. RUNNING PROCESSES"
# ------------------------------------------------------------
ps -eo pid,ppid,user,lstart,etime,args | grep -Ei "$TARGET|wallpaper|variety|deviousq" | grep -v grep

# ------------------------------------------------------------
sec "2. SYSTEMD SYSTEM SERVICES"
# ------------------------------------------------------------
systemctl list-units --all --type=service 2>/dev/null | grep -Ei "wallpaper|random"
systemctl list-unit-files 2>/dev/null | grep -Ei "wallpaper|random"
echo
echo "--- full cat of any matching unit ---"
for u in $(systemctl list-unit-files 2>/dev/null | awk '{print $1}' | grep -Ei "wallpaper|random"); do
    echo "### $u"
    systemctl cat "$u" 2>/dev/null
    echo
done

# ------------------------------------------------------------
sec "3. SYSTEMD SYSTEM TIMERS"
# ------------------------------------------------------------
systemctl list-timers --all 2>/dev/null | grep -Ei "wallpaper|random" || echo "(none)"
systemctl list-unit-files --type=timer 2>/dev/null | grep -Ei "wallpaper|random" || echo "(none)"

# ------------------------------------------------------------
sec "4. SYSTEMD USER SERVICES"
# ------------------------------------------------------------
systemctl --user list-units --all --type=service 2>/dev/null | grep -Ei "wallpaper|random"
systemctl --user list-unit-files 2>/dev/null | grep -Ei "wallpaper|random"
echo
echo "--- full cat of any matching user unit ---"
for u in $(systemctl --user list-unit-files 2>/dev/null | awk '{print $1}' | grep -Ei "wallpaper|random"); do
    echo "### $u"
    systemctl --user cat "$u" 2>/dev/null
    echo
done

# ------------------------------------------------------------
sec "5. SYSTEMD USER TIMERS"
# ------------------------------------------------------------
systemctl --user list-timers --all 2>/dev/null | grep -Ei "wallpaper|random" || echo "(none)"
systemctl --user list-unit-files --type=timer 2>/dev/null | grep -Ei "wallpaper|random" || echo "(none)"

# ------------------------------------------------------------
sec "6. SYSTEMD JOURNAL (recent unit activity)"
# ------------------------------------------------------------
journalctl --since "3 hours ago" 2>/dev/null \
    | grep -Ei "wallpaper|random_wallpaper" \
    | tail -50 || echo "(nothing)"

journalctl --user --since "3 hours ago" 2>/dev/null \
    | grep -Ei "wallpaper|random_wallpaper" \
    | tail -50 || echo "(nothing user)"

# ------------------------------------------------------------
sec "7. CRON - USER"
# ------------------------------------------------------------
crontab -l 2>/dev/null | grep -Ei "wallpaper|random" || echo "(no user crontab entries)"
crontab -l 2>/dev/null || echo "(no user crontab at all)"

# ------------------------------------------------------------
sec "8. CRON - SYSTEM"
# ------------------------------------------------------------
for f in /etc/crontab /etc/cron.d/* /etc/cron.hourly/* /etc/cron.daily/* \
         /etc/cron.weekly/* /etc/cron.monthly/*; do
    [ -f "$f" ] || continue
    if grep -qiE "wallpaper|random" "$f" 2>/dev/null; then
        echo "### $f"
        grep -iE "wallpaper|random" "$f"
        echo
    fi
done
echo "(scan complete)"

# ------------------------------------------------------------
sec "9. ANACRON"
# ------------------------------------------------------------
cat /etc/anacrontab 2>/dev/null | grep -Ei "wallpaper|random" || echo "(no matches)"
cat /etc/anacrontab 2>/dev/null || echo "(no /etc/anacrontab)"

# ------------------------------------------------------------
sec "10. AT JOBS"
# ------------------------------------------------------------
atq 2>/dev/null || echo "(atq not available or no jobs)"

# ------------------------------------------------------------
sec "11. SUPERVISORD"
# ------------------------------------------------------------
if command -v supervisorctl >/dev/null 2>&1; then
    supervisorctl status 2>/dev/null
else
    echo "(supervisorctl not installed)"
fi
find /etc/supervisor /etc/supervisord* /etc/supervisor.d -type f 2>/dev/null \
    | xargs -r grep -liE "wallpaper|random" 2>/dev/null

# ------------------------------------------------------------
sec "12. RUNIT / S6 / OPENRC"
# ------------------------------------------------------------
echo "--- runit ---"
ls -la /etc/service/ 2>/dev/null | grep -iE "wallpaper|random" || echo "(none)"
ls -la /etc/sv/ 2>/dev/null | grep -iE "wallpaper|random" || echo "(none)"
echo "--- s6 ---"
ls -la /etc/s6/ /etc/s6-rc/ 2>/dev/null || echo "(none)"
echo "--- OpenRC ---"
rc-update show 2>/dev/null | grep -iE "wallpaper|random" || echo "(not OpenRC or none)"

# ------------------------------------------------------------
sec "13. KDE AUTOSTART"
# ------------------------------------------------------------
ls -la ~/.config/autostart/ 2>/dev/null
ls -la /etc/xdg/autostart/ 2>/dev/null | grep -iE "wallpaper|random"
echo "--- grep for wallpaper in autostart ---"
grep -rilE "wallpaper|random_wallpaper" ~/.config/autostart/ /etc/xdg/autostart/ 2>/dev/null

# ------------------------------------------------------------
sec "14. XDG AUTOSTART DESKTOP FILES"
# ------------------------------------------------------------
find ~/.config/autostart /etc/xdg/autostart -name "*.desktop" 2>/dev/null \
    | xargs -r grep -lE "wallpaper|random" 2>/dev/null

# ------------------------------------------------------------
sec "15. SHELL RC FILES"
# ------------------------------------------------------------
for f in ~/.bashrc ~/.bash_profile ~/.profile ~/.zshrc ~/.zprofile ~/.zlogin \
         ~/.config/fish/config.fish /etc/profile /etc/bash.bashrc; do
    [ -f "$f" ] || continue
    if grep -qiE "wallpaper|random_wallpaper" "$f" 2>/dev/null; then
        echo "### $f"
        grep -niE "wallpaper|random_wallpaper" "$f"
    fi
done
echo "(scan complete)"

# ------------------------------------------------------------
sec "16. XINITRC / XPROFILE / XSESSION"
# ------------------------------------------------------------
for f in ~/.xinitrc ~/.xprofile ~/.xsession ~/.xsessionrc; do
    [ -f "$f" ] || continue
    if grep -qiE "wallpaper|random_wallpaper" "$f" 2>/dev/null; then
        echo "### $f"
        grep -niE "wallpaper|random_wallpaper" "$f"
    fi
done
echo "(scan complete)"

# ------------------------------------------------------------
sec "17. LOGIN / PROFILE.D"
# ------------------------------------------------------------
grep -rilE "wallpaper|random_wallpaper" /etc/profile.d/ 2>/dev/null
for f in /etc/profile.d/*.sh; do
    [ -f "$f" ] || continue
    grep -niE "wallpaper|random_wallpaper" "$f" 2>/dev/null
done

# ------------------------------------------------------------
sec "18. TMUX / SCREEN SESSIONS"
# ------------------------------------------------------------
tmux ls 2>/dev/null || echo "(no tmux)"
screen -ls 2>/dev/null || echo "(no screen)"

# ------------------------------------------------------------
sec "19. DOCKER / PODMAN"
# ------------------------------------------------------------
docker ps 2>/dev/null | grep -iE "wallpaper|random" || echo "(no docker matches or docker unavailable)"
podman ps 2>/dev/null | grep -iE "wallpaper|random" || echo "(no podman matches or podman unavailable)"

# ------------------------------------------------------------
sec "20. WHOLE-SYSTEM GREP FOR THE SCRIPT NAME"
# ------------------------------------------------------------
echo "Searching common config locations for '$TARGET'..."
grep -rilE "$TARGET" \
    ~/.config ~/.local ~/.bashrc ~/.profile \
    /etc/systemd /etc/xdg /etc/cron* /etc/profile.d \
    /usr/lib/systemd /lib/systemd 2>/dev/null \
    | head -50
echo "(done)"

# ------------------------------------------------------------
sec "21. WHOLE-SYSTEM FIND FOR THE SCRIPT FILE"
# ------------------------------------------------------------
echo "Searching for the script file itself..."
find / -maxdepth 6 \
    \( -path /proc -o -path /sys -o -path /dev -o -path /run -o -path /tmp \) -prune -o \
    -type f -name "*${TARGET}*" -print 2>/dev/null | head -50

# ------------------------------------------------------------
sec "22. SYSTEMD ALL UNITS CONTAINING SCRIPT PATH"
# ------------------------------------------------------------
grep -rilE "wallpaper" /etc/systemd /lib/systemd /usr/lib/systemd ~/.config/systemd 2>/dev/null

# ------------------------------------------------------------
sec "23. AUDIT / INOTIFY WATCHERS"
# ------------------------------------------------------------
echo "--- auditd rules ---"
auditctl -l 2>/dev/null | grep -iE "wallpaper|random" || echo "(none or auditctl unavailable)"
echo "--- inotify watchers on script dir ---"
if command -v inotifywait >/dev/null 2>&1; then
    echo "(inotifywait installed - run manually: inotifywait -m -r ~/scriptlogs)"
else
    echo "(inotifywait not installed)"
fi

# ------------------------------------------------------------
sec "24. RECENT PROCESS HISTORY (from journal if present)"
# ------------------------------------------------------------
journalctl --since "3 hours ago" 2>/dev/null \
    | grep -Ei "Started|Stopped|Scheduled|random_wallpaper" \
    | tail -80

# ------------------------------------------------------------
sec "25. LOGGER / TERMINAL PARENT"
# ------------------------------------------------------------
echo "Current shell tree:"
pstree -aps $$ 2>/dev/null || ps -ef --forest 2>/dev/null | head -40

# ------------------------------------------------------------
sec "26. LOG ROTATION / WATCHDOG SCRIPTS"
# ------------------------------------------------------------
find ~ -maxdepth 4 -type f \( -name "*.sh" -o -name "*.py" -o -name "*.service" \) 2>/dev/null \
    | xargs -r grep -liE "random_wallpaper|wallpaper\.sh" 2>/dev/null \
    | grep -v "$TARGET.sh" | head -30

# ------------------------------------------------------------
sec "27. THE CRON/CONFIG OF THE USER"
# ------------------------------------------------------------
echo "--- groups ---"
groups
echo "--- shell ---"
echo "$SHELL"
echo "--- login shells active ---"
who -a 2>/dev/null

# ------------------------------------------------------------
sec "SUMMARY - KEY FINDINGS"
# ------------------------------------------------------------
echo
echo "If nothing above matched, the restarter is likely one of:"
echo "  a) a systemd unit/timer named something unrelated but referencing"
echo "     the script path"
echo "  b) a wrapper script / cron entry under a different name"
echo "  c) an autostart entry in the desktop environment"
echo "  d) a manual 'while true; do ... sleep 30; done' loop somewhere"
echo
echo "Report saved to: $LOG"
