#!/usr/bin/env bash
set -euo pipefail

# Load the GNOME snapshots into dconf and install the extensions listed in
# gnome/extensions-all.txt that are missing (from extensions.gnome.org, the
# release made for the installed GNOME Shell).
# Works without a running session (e.g. from the installer): it then starts
# its own D-Bus session for dconf. DOTFILES_YES=1 skips the confirmation.

repo="${DOTFILES_DIR:-$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")}"
base="$repo/gnome"
areas=(desktop shell mutter settings-daemon)
backup_dir="$HOME/dotfiles-backups/gnome-$(date +%Y%m%d-%H%M%S)"
ext_dir="$HOME/.local/share/gnome-shell/extensions"

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  printf 'Run as your user, not root: dconf settings are per user.\n' >&2
  exit 1
fi

# dconf writes through its D-Bus service: outside a session, bring one up.
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  exec dbus-run-session -- "$(realpath "$0")" "$@"
fi

for area in "${areas[@]}"; do
  if [ ! -f "$base/$area.dconf" ]; then
    printf 'Missing snapshot: %s\n' "$base/$area.dconf" >&2
    exit 1
  fi
done

printf 'This will load %s into dconf (merge: keys in the snapshot win)\n' "$base"
printf 'and install the missing extensions of %s/extensions-all.txt.\n' "$base"
printf 'Current settings will be backed up to %s.\n' "$backup_dir"
if [ "${DOTFILES_YES:-0}" != 1 ]; then
  printf 'Type APPLY_GNOME to continue: '
  read -r answer
  if [ "$answer" != "APPLY_GNOME" ]; then
    printf 'Aborted.\n'
    exit 1
  fi
fi

install_extension() {
  local uuid=$1 shell=$2 url tmp
  url="$(curl -fsS --max-time 20 \
    "https://extensions.gnome.org/extension-info/?uuid=$uuid&shell_version=$shell" |
    grep -oP '"download_url":\s*"\K[^"]+')" || return 1
  tmp="$(mktemp -d)"
  curl -fsSL --max-time 60 -o "$tmp/ext.zip" "https://extensions.gnome.org$url" &&
    mkdir -p "$ext_dir/$uuid" &&
    bsdtar -xf "$tmp/ext.zip" -C "$ext_dir/$uuid"
  local status=$?
  rm -rf "$tmp"
  [ "$status" -eq 0 ] || return 1
  # Settings schemas must be compiled for GNOME to read their keys.
  if [ -d "$ext_dir/$uuid/schemas" ] && [ ! -f "$ext_dir/$uuid/schemas/gschemas.compiled" ]; then
    glib-compile-schemas "$ext_dir/$uuid/schemas"
  fi
}

failed=()
if [ -f "$base/extensions-all.txt" ] && command -v gnome-shell >/dev/null 2>&1; then
  shell="$(gnome-shell --version | grep -oE '[0-9]+' | head -1)"
  while IFS= read -r uuid; do
    [ -n "$uuid" ] || continue
    if [ -d "$ext_dir/$uuid" ] || [ -d "/usr/share/gnome-shell/extensions/$uuid" ]; then
      continue
    fi
    if install_extension "$uuid" "$shell"; then
      printf 'installed extension %s\n' "$uuid"
    else
      failed+=("$uuid")
    fi
  done < "$base/extensions-all.txt"
fi

mkdir -p "$backup_dir"
dconf dump / > "$backup_dir/dconf-full.dconf"

for area in "${areas[@]}"; do
  dconf load "/org/gnome/$area/" < "$base/$area.dconf"
  printf 'loaded /org/gnome/%s/\n' "$area"
done

printf 'GNOME settings loaded. Restore previous state with:\n'
printf '  dconf load / < %s/dconf-full.dconf\n' "$backup_dir"
if [ "${#failed[@]}" -gt 0 ]; then
  printf 'Extensions not available for GNOME Shell %s: %s\n' "$shell" "${failed[*]}"
fi
printf 'Extensions take effect at the next GNOME login.\n'
