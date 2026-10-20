#!/usr/bin/env bash
set -euo pipefail

# Save the package and service lists of the live system into packages/.
#   native.txt           explicitly installed packages from the official repos
#   aur.txt              explicitly installed foreign packages (AUR)
#   flatpak.txt          installed Flatpak apps
#   services-system.txt  enabled system units
#   services-user.txt    enabled user units
# Names in skip.txt are left out of every list.

repo="${DOTFILES_DIR:-$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")}"
out="$repo/packages"

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  printf 'Run as your user, not root: user units are per user.\n' >&2
  exit 1
fi

mkdir -p "$out"

skip() {
  if [ -s "$out/skip.txt" ]; then
    grep -vxFf <(grep -v '^#' "$out/skip.txt" | grep .) || true
  else
    cat
  fi
}

pacman -Qqen | skip | sort > "$out/native.txt"
printf 'pulled %s native packages\n' "$(wc -l < "$out/native.txt")"

pacman -Qqem | skip | sort > "$out/aur.txt"
printf 'pulled %s AUR packages\n' "$(wc -l < "$out/aur.txt")"

if command -v flatpak >/dev/null 2>&1; then
  flatpak list --app --columns=application | skip | sort > "$out/flatpak.txt"
  printf 'pulled %s flatpak apps\n' "$(wc -l < "$out/flatpak.txt")"
else
  printf 'skip flatpak list: flatpak not found\n'
fi

# Only units enabled by hand matter: static and generated units come back
# with their packages.
systemctl list-unit-files --state=enabled --no-legend --no-pager |
  awk '{print $1}' | skip | sort > "$out/services-system.txt"
printf 'pulled %s system units\n' "$(wc -l < "$out/services-system.txt")"

systemctl --user list-unit-files --state=enabled --no-legend --no-pager |
  awk '{print $1}' | skip | sort > "$out/services-user.txt"
printf 'pulled %s user units\n' "$(wc -l < "$out/services-user.txt")"

# Python tools installed outside pacman (uv tool, pipx, pip --user).
if command -v uv >/dev/null 2>&1; then
  uv tool list 2>/dev/null | awk '/^[^- ]/ {print $1}' | skip | sort > "$out/uv-tools.txt"
  printf 'pulled %s uv tools\n' "$(grep -c . "$out/uv-tools.txt")"
fi
if command -v pipx >/dev/null 2>&1; then
  pipx list --short 2>/dev/null | awk '{print $1}' | skip | sort > "$out/pipx.txt"
  printf 'pulled %s pipx tools\n' "$(grep -c . "$out/pipx.txt")"
fi
python3 -m pip list --user --format=freeze 2>/dev/null | cut -d= -f1 | skip | sort > "$out/pip-user.txt"
printf 'pulled %s pip --user packages\n' "$(grep -c . "$out/pip-user.txt")"

printf 'Package lists updated under %s.\n' "$out"
