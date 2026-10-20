#!/usr/bin/env bash
# Wait until a system tray exists (up to 20 seconds), then exit 0.
#
# Apps like Proton VPN check for a tray only once, when they start. If they
# start before the tray (the Caelestia shell in Hyprland, the AppIndicator
# extension in GNOME), they run without a tray icon and quit when you close
# the window.
# Used by ~/.config/systemd/user/app-protonvpn@autostart.service.d/.
# It never fails: after 20 seconds the app starts anyway.

for _ in $(seq 40); do
    busctl --user status org.kde.StatusNotifierWatcher >/dev/null 2>&1 && exit 0
    sleep 0.5
done
exit 0
