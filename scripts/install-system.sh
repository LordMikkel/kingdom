#!/usr/bin/env bash
set -euo pipefail

repo="${DOTFILES_DIR:-$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")}"
base="$repo/system/etc"
backup_dir="/var/backups/dotfiles-system-$(date +%Y%m%d-%H%M%S)"

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  exec sudo DOTFILES_DIR="$repo" "$(realpath "$0")" "$@"
fi

if [ ! -d "$base" ]; then
  printf 'Missing system snapshot directory: %s\n' "$base" >&2
  exit 1
fi

printf 'This will copy files from %s into /etc.\n' "$base"
printf 'Backups will be written to %s.\n' "$backup_dir"
printf 'Type APPLY_SYSTEM to continue: '
read -r answer
if [ "$answer" != "APPLY_SYSTEM" ]; then
  printf 'Aborted.\n'
  exit 1
fi

while IFS= read -r snapshot; do
  rel="${snapshot#$repo/system}"
  live="$rel"
  mkdir -p "$(dirname "$live")" "$backup_dir$(dirname "$live")"
  if [ -e "$live" ] || [ -L "$live" ]; then
    cp -a "$live" "$backup_dir$live"
  fi
  mode=0644
  # Root-only: run by root, so the user must not read or edit them.
  case "$live" in
    /etc/opensnitchd/rules/*|/etc/usbguard/*|/etc/ssh/sshd_config) mode=0600 ;;
    /usr/local/bin/*) mode=0755 ;;
  esac
  install -m "$mode" "$snapshot" "$live"
  printf 'installed %s\n' "$live"
done < <(find "$base" "$repo/system/usr/local" -type f 2>/dev/null | sort)

printf 'System files installed. Review backup at %s.\n' "$backup_dir"
