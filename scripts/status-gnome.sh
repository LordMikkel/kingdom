#!/usr/bin/env bash
set -euo pipefail

repo="${DOTFILES_DIR:-$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")}"
base="$repo/gnome"
areas=(desktop shell mutter settings-daemon)

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  printf 'Run as your user, not root: dconf settings are per user.\n' >&2
  exit 1
fi

for area in "${areas[@]}"; do
  snapshot="$base/$area.dconf"
  if [ ! -f "$snapshot" ]; then
    printf 'missing snapshot %s\n' "$snapshot"
    continue
  fi
  if dconf dump "/org/gnome/$area/" | cmp -s "$snapshot" -; then
    printf 'same /org/gnome/%s/\n' "$area"
  else
    printf '\n--- diff /org/gnome/%s/\n' "$area"
    dconf dump "/org/gnome/$area/" | diff -u "$snapshot" - || true
  fi
done

if command -v gnome-extensions >/dev/null 2>&1 \
  && [ -f "$base/extensions-enabled.txt" ]; then
  if gnome-extensions list --enabled | cmp -s "$base/extensions-enabled.txt" -; then
    printf 'same enabled extensions\n'
  else
    printf '\n--- diff enabled extensions\n'
    gnome-extensions list --enabled | diff -u "$base/extensions-enabled.txt" - || true
  fi
fi
