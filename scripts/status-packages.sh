#!/usr/bin/env bash
set -euo pipefail

# Compare packages/ with the live system (read-only).
#   + installed or enabled now, missing from the repo list
#   - in the repo list, missing from the live system

repo="${DOTFILES_DIR:-$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")}"
base="$repo/packages"

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  printf 'Run as your user, not root: user units are per user.\n' >&2
  exit 1
fi

skip() {
  if [ -s "$base/skip.txt" ]; then
    grep -vxFf <(grep -v '^#' "$base/skip.txt" | grep .) || true
  else
    cat
  fi
}

compare() {
  name="$1"
  shift
  list="$base/$name"
  if [ ! -f "$list" ]; then
    printf 'missing list %s (run pull-packages.sh)\n' "$list"
    return
  fi
  live="$("$@" | skip | sort)"
  if [ "$live" = "$(cat "$list")" ]; then
    printf 'same %s\n' "$name"
    return
  fi
  printf '\n--- diff %s\n' "$name"
  comm -13 "$list" <(printf '%s\n' "$live") | sed 's/^/+ /'
  comm -23 "$list" <(printf '%s\n' "$live") | sed 's/^/- /'
}

units() {
  systemctl "$@" list-unit-files --state=enabled --no-legend --no-pager |
    awk '{print $1}'
}

compare native.txt pacman -Qqen
compare aur.txt pacman -Qqem
if command -v flatpak >/dev/null 2>&1; then
  compare flatpak.txt flatpak list --app --columns=application
fi
compare services-system.txt units --system
compare services-user.txt units --user
if command -v uv >/dev/null 2>&1; then
  compare uv-tools.txt sh -c "uv tool list 2>/dev/null | awk '/^[^- ]/ {print \$1}'"
fi
if command -v pipx >/dev/null 2>&1; then
  compare pipx.txt sh -c "pipx list --short 2>/dev/null | awk '{print \$1}'"
fi
compare pip-user.txt sh -c "python3 -m pip list --user --format=freeze 2>/dev/null | cut -d= -f1"
