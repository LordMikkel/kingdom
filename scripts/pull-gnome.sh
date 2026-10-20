#!/usr/bin/env bash
set -euo pipefail

repo="${DOTFILES_DIR:-$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")}"
out="$repo/gnome"
areas=(desktop shell mutter settings-daemon)

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  printf 'Run as your user, not root: dconf settings are per user.\n' >&2
  exit 1
fi

# Outside GNOME, ~/Scripts/session-theme.sh has switched the theme keys to
# the Hyprland ones: a pull there would save them as the GNOME settings.
case "${XDG_CURRENT_DESKTOP:-}" in
  *GNOME*) ;;
  *)
    if [ "${1:-}" != --force ]; then
      printf 'Run it from a GNOME session (now: %s), or pass --force.\n' \
        "${XDG_CURRENT_DESKTOP:-none}" >&2
      exit 1
    fi
    ;;
esac

if ! command -v dconf >/dev/null 2>&1; then
  printf 'dconf is not installed.\n' >&2
  exit 1
fi

mkdir -p "$out"

for area in "${areas[@]}"; do
  dconf dump "/org/gnome/$area/" > "$out/$area.dconf"
  printf 'pulled /org/gnome/%s/\n' "$area"
done

# Full dump contains private paths (recent folders, file names): git-ignored.
dconf dump / > "$out/dconf-full.local.dconf"
printf 'pulled full dump (local only)\n'

# gnome-extensions needs a running GNOME Shell; without one, read the
# extension folders and dconf instead of writing empty lists.
if all="$(gnome-extensions list 2>/dev/null)" &&
  enabled="$(gnome-extensions list --enabled 2>/dev/null)"; then
  printf '%s\n' "$all" > "$out/extensions-all.txt"
  printf '%s\n' "$enabled" > "$out/extensions-enabled.txt"
else
  all="$(ls "$HOME/.local/share/gnome-shell/extensions" \
    /usr/share/gnome-shell/extensions 2>/dev/null | grep '@' | sort -u)"
  printf '%s\n' "$all" > "$out/extensions-all.txt"
  dconf read /org/gnome/shell/enabled-extensions | grep -oE "'[^']+'" | tr -d "'" |
    grep -xF -f <(printf '%s\n' "$all") > "$out/extensions-enabled.txt" || true
fi
printf 'pulled extension lists\n'

printf 'GNOME snapshots updated under %s.\n' "$out"
