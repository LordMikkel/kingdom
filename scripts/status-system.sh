#!/usr/bin/env bash
set -euo pipefail

repo="${DOTFILES_DIR:-$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")}"
base="$repo/system/etc"

if [ ! -d "$base" ]; then
  printf 'Missing system snapshot directory: %s\n' "$base" >&2
  exit 1
fi

while IFS= read -r snapshot; do
  rel="${snapshot#$repo/system}"
  live="$rel"
  if [ ! -e "$live" ]; then
    if [ ! -r "$(dirname "$live")" ] || [ ! -x "$(dirname "$live")" ]; then
      printf 'needs sudo %s\n' "$live"
      continue
    fi
    printf 'missing live %s\n' "$live"
    continue
  fi
  if [ ! -r "$live" ]; then
    printf 'needs sudo %s\n' "$live"
    continue
  fi
  if cmp -s "$snapshot" "$live"; then
    printf 'same %s\n' "$live"
  else
    printf '\n--- diff %s\n' "$live"
    diff -u "$snapshot" "$live" || true
  fi
done < <(find "$base" "$repo/system/usr/local" -type f 2>/dev/null | sort)
