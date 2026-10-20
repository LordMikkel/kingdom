#!/usr/bin/env bash
set -euo pipefail

repo="${DOTFILES_DIR:-$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")}"
package="$repo/home"

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  printf 'Run as your user, not root: targets live in your $HOME.\n' >&2
  exit 1
fi
backup_dir="$HOME/dotfiles-backups/home-$(date +%Y%m%d-%H%M%S)"

if [ ! -d "$package" ]; then
  printf 'Missing home package: %s\n' "$package" >&2
  exit 1
fi

if ! command -v stow >/dev/null 2>&1; then
  printf 'stow is not installed.\n' >&2
  exit 1
fi

printf 'Checking existing home targets...\n'
while IFS= read -r source; do
  rel="${source#$package/}"
  target="$HOME/$rel"
  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    continue
  fi
  # Already linked: the target is a symlink to the source, or it sits inside
  # a folded directory symlink (e.g. ~/.config/hypr -> repo), so it is the
  # repo file itself and must never be moved.
  if [ "$(readlink -f "$target")" = "$(readlink -f "$source")" ]; then
    continue
  fi
  if cmp -s "$source" "$target"; then
    printf 'backup identical %s\n' "$target"
    mkdir -p "$backup_dir/$(dirname "$rel")"
    mv "$target" "$backup_dir/$rel"
    continue
  fi
  printf 'Conflict: %s differs from %s\n' "$target" "$source" >&2
  printf 'Aborting without changing this target. Resolve it manually first.\n' >&2
  exit 1
done < <(find "$package" -path '*/.git/*' -prune -o -type f -print | sort)

printf 'Checking stow plan for home package...\n'
stow --no --verbose --dir "$repo" --target "$HOME" home

if [ "${DOTFILES_YES:-0}" != 1 ]; then
  printf '\nApply these home symlinks? Type YES to continue: '
  read -r answer
  if [ "$answer" != "YES" ]; then
    printf 'Aborted.\n'
    exit 1
  fi
fi

# Only these folders are linked whole; every other folder is created as a
# real directory so stow links just the files inside. Otherwise, on a fresh
# $HOME, stow would link ~/.config itself and every app would write its
# state into the repo. systemd also ignores drop-in directories that are
# symlinks.
folded=(.config/hypr .config/uwsm .config/caelestia .config/cliphist .config/Thunar)
find "$package" -mindepth 1 -path '*/.git' -prune -o -type d -print |
  while IFS= read -r dir; do
    rel="${dir#$package/}"
    for f in "${folded[@]}"; do
      case "$rel/" in "$f"/*) continue 2 ;; esac
    done
    mkdir -p "$HOME/$rel"
  done

stow --verbose --dir "$repo" --target "$HOME" home
printf 'Home symlinks installed.\n'
