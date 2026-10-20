#!/usr/bin/env bash
# Keep the GNOME and Caelestia (Hyprland) looks apart. Both sessions share
# the same dconf keys and ~/.config/gtk-{3,4}.0/gtk.css, so each session puts
# its own look back at login:
#   session-theme gnome     from ~/.config/autostart/session-theme-gnome.desktop
#   session-theme hyprland  from ~/.config/caelestia/hypr-user.lua
set -euo pipefail

cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
iface=org.gnome.desktop.interface

case "${1:-}" in
  gnome)
    # Values from ~/dotfiles/gnome/desktop.dconf. gtk-theme is not set
    # there, so it goes back to its default (Adwaita).
    gsettings reset "$iface" gtk-theme
    gsettings set "$iface" icon-theme 'Adwaita'
    gsettings set "$iface" cursor-theme 'Adwaita'
    # GTK and libadwaita apps load gtk.css by themselves: hide Caelestia's.
    for v in gtk-3.0 gtk-4.0; do
      if [ -f "$cfg/$v/gtk.css" ]; then
        mv -f "$cfg/$v/gtk.css" "$cfg/$v/gtk.css.caelestia"
      fi
    done
    ;;
  hyprland)
    for v in gtk-3.0 gtk-4.0; do
      if [ -f "$cfg/$v/gtk.css.caelestia" ]; then
        mv -f "$cfg/$v/gtk.css.caelestia" "$cfg/$v/gtk.css"
      fi
    done
    # Re-apply the current scheme: rewrites gtk.css and sets Caelestia's
    # gtk-theme and icon-theme again. The cursor is set by its execs.lua.
    caelestia scheme set -n "$(caelestia scheme get -n)"
    ;;
  *)
    printf 'usage: %s gnome|hyprland\n' "${0##*/}" >&2
    exit 2
    ;;
esac
