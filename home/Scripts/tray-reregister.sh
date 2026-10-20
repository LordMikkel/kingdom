#!/usr/bin/env bash
# Put tray icons back after the Caelestia shell restarts.
#
# The tray (StatusNotifierWatcher) lives in the Caelestia shell. When the shell
# restarts, apps must register their icon again; some do (OpenSnitch), Proton
# VPN does not, so its icon disappears while the app keeps running. Every few
# seconds, register again any icon an app still offers on D-Bus
# (org.kde.StatusNotifierItem-*) that the tray does not list.
# Started from ~/.config/caelestia/hypr-user.lua (Hyprland only).

watcher=org.kde.StatusNotifierWatcher

# Only one copy (Hyprland reloads do not restart it, but a new login would).
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/tray-reregister.lock"
flock -n 9 || exit 0

while sleep 5; do
    registered=$(busctl --user get-property "$watcher" /StatusNotifierWatcher \
        "$watcher" RegisteredStatusNotifierItems 2>/dev/null) || continue
    busctl --user list --no-legend 2>/dev/null |
        awk '$1 ~ /^org\.kde\.StatusNotifierItem-/ { print $1 }' |
        while read -r item; do
            case "$registered" in
                *"\"$item/"*|*"\"$item\""*) ;;
                *) busctl --user call "$watcher" /StatusNotifierWatcher "$watcher" \
                       RegisterStatusNotifierItem s "$item" >/dev/null 2>&1 ;;
            esac
        done
done
