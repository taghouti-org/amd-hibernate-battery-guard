#!/bin/sh
# /usr/lib/systemd/system-sleep/resume-health-check.sh
#
# Post-resume health check. Two failure modes can leave the system degraded after
# resume without any visible sign:
#  - Firmware page-faults during an EFI runtime call -> kernel disables EFI Runtime
#    Services (efivars empty, efibootmgr/fwupd broken until reboot).
#  - amdgpu ring timeout with a failed GPU reset -> desktop stuck, sleep impossible.
# This only warns the logged-in user(s) with a desktop notification so they can reboot.
[ "$1" = "post" ] || exit 0

notify() {
    for bus in /run/user/*/bus; do
        [ -S "$bus" ] || continue
        uid=$(stat -c %u "$bus")
        user=$(id -nu "$uid" 2>/dev/null) || continue
        runuser -u "$user" -- env DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
            notify-send -u critical -a "Resume check" -i dialog-warning "$1" "$2"
    done
    logger -t resume-health-check "$1: $2"
}

(
    # Kernel resume messages are stamped at resume time, just before this hook runs.
    since=$(date -d '-1 min' '+%F %T')
    sleep 20
    if journalctl -k --since "$since" -q | grep -q "EFI Runtime Services are disabled"; then
        notify "Firmware fault after resume" \
            "EFI runtime services were disabled by a firmware bug. Boot entries and firmware updates won't work until you reboot."
    fi
    if journalctl -k --since "$since" -q | grep -qE "GPU Recovery Failed|Ring .* reset failed"; then
        notify "Graphics crashed after resume" \
            "The GPU failed to recover. Save your work and reboot now; sleep and hibernate will not work."
    fi
) </dev/null >/dev/null 2>&1 &
exit 0
