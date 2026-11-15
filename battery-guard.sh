#!/bin/sh
# Last-resort safety net: power off cleanly if the battery is at or below LIMIT%
# while discharging. Protects against a failed-sleep loop draining the battery to 0%.
LIMIT=${BATTERY_GUARD_LIMIT:-2}
for BAT in /sys/class/power_supply/BAT*; do
    [ -r "$BAT/capacity" ] || continue
    cap=$(cat "$BAT/capacity")
    status=$(cat "$BAT/status")
    if [ "$status" = "Discharging" ] && [ "$cap" -le "$LIMIT" ]; then
        logger -t battery-guard "$(basename "$BAT") at ${cap}% and discharging, powering off"
        systemctl poweroff
        exit 0
    fi
done
