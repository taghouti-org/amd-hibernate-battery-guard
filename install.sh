#!/bin/sh
# Installer for the hibernate / battery-drain fixes.
#   sudo sh install.sh                     install hibernate-mode, battery-guard, resume check
#   sudo sh install.sh --charge-limit 80   also cap charging at 80% (resume below 75%)
#   sudo sh install.sh --uninstall         remove everything this script installed
set -e
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo." >&2; exit 1; }
cd "$(dirname "$0")"

SLEEP_HOOK_DIR=/usr/lib/systemd/system-sleep
LIMIT_CONF=/etc/tmpfiles.d/battery-charge-limit.conf

if [ "$1" = "--uninstall" ]; then
    systemctl disable --now battery-guard.timer 2>/dev/null || true
    rm -f /etc/systemd/sleep.conf.d/hibernate-mode.conf \
          /usr/local/sbin/battery-guard.sh \
          /etc/systemd/system/battery-guard.service /etc/systemd/system/battery-guard.timer \
          "$SLEEP_HOOK_DIR/resume-health-check.sh" "$LIMIT_CONF"
    systemctl daemon-reload
    echo "Removed. (A charge limit already applied stays until reboot.)"
    exit 0
fi

install -Dm644 hibernate-mode.conf /etc/systemd/sleep.conf.d/hibernate-mode.conf
install -Dm755 battery-guard.sh /usr/local/sbin/battery-guard.sh
install -Dm644 battery-guard.service /etc/systemd/system/battery-guard.service
install -Dm644 battery-guard.timer /etc/systemd/system/battery-guard.timer
install -Dm755 resume-health-check.sh "$SLEEP_HOOK_DIR/resume-health-check.sh"
systemctl daemon-reload
systemctl enable --now battery-guard.timer
echo "Installed: HibernateMode=shutdown, battery-guard.timer, resume-health-check hook."

if [ "$1" = "--charge-limit" ]; then
    end=${2:?usage: --charge-limit <percent>}
    start=$((end - 5))
    bat=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
    [ -w "$bat/charge_control_end_threshold" ] || { echo "This battery has no charge threshold support." >&2; exit 1; }
    cat > "$LIMIT_CONF" <<CONF
# Battery charge limit: stop at ${end}%, resume below ${start}%.
w $bat/charge_control_start_threshold - - - - $start
w $bat/charge_control_end_threshold - - - - $end
CONF
    systemd-tmpfiles --create "$LIMIT_CONF"
    echo "Charge limit set: ${start}-${end}% ($(basename "$bat"))."
fi
