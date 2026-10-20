#!/usr/bin/env bash
set -euo pipefail

repo="${DOTFILES_DIR:-$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")}"
home_package="$repo/home"

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  printf 'Run as your user, not root: targets live in your $HOME.\n' >&2
  exit 1
fi

if [ ! -d "$home_package" ]; then
  printf 'Missing home package: %s\n' "$home_package" >&2
  exit 1
fi

while IFS= read -r source; do
  rel="${source#$home_package/}"
  target="$HOME/$rel"
  if [ -L "$target" ]; then
    link_target="$(readlink "$target")"
    if [ "$(readlink -f "$target")" = "$(readlink -f "$source")" ]; then
      printf 'linked   %s -> %s\n' "$target" "$link_target"
    else
      printf 'mismatch %s -> %s\n' "$target" "$link_target"
    fi
  elif [ "$(readlink -f "$target")" = "$(readlink -f "$source")" ]; then
    # Inside a directory that stow linked as a whole (folding).
    printf 'linked   %s (via linked folder)\n' "$target"
  elif [ -e "$target" ]; then
    printf 'real     %s\n' "$target"
  else
    printf 'missing  %s\n' "$target"
  fi
done < <(find "$home_package" -path '*/.git/*' -prune -o -type f -print | sort)
