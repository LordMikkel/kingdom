#!/usr/bin/env bash
set -euo pipefail

# List /etc files that differ from a fresh install but are not in
# system/etc (read-only). Run with sudo to also see root-only folders.
#   modified  config shipped by a package and edited since
#   unowned   file no package owns (made by hand or by a tool)
# Add the ones you care about to pull-system.sh and run it.

repo="${DOTFILES_DIR:-$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")}"
base="$repo/system"

tracked() { [ -e "$base$1" ]; }

# Generated, secret or per-machine state that a reinstall recreates by itself.
skip_re='^/etc/(\.pwd\.lock|\.updated|ld\.so\.cache|machine-id|adjtime|localtime|hostname|hosts|locale\.conf|vconsole\.conf|mtab|resolv\.conf|os-release|shadow|gshadow|passwd|group|subuid|subgid|brlapi\.key|xml/catalog|audit/audit\.rules|dconf/db/[^/]+$|ssh/ssh_host_|pacman\.d/(gnupg|mirrorlist)|ssl/certs|ca-certificates|NetworkManager/system-connections|pki|machine-info|udev/hwdb\.bin|systemd/(system|user)/[^/]+\.wants)'
# Backups left by editors, tools and pacman.
skip_suffix_re='(\.pacnew|\.pacsave|-|~|\.(bak|prev|original|old|OLD)(\.[0-9-]+)?)$'

skip() { [[ "$1" =~ $skip_re ]] || [[ "$1" =~ $skip_suffix_re ]]; }

# Folders with many files (opensnitch rules, ...) are shown as one line.
collapse() {
  awk '{ n = split($2, p, "/"); dir = $2; sub("/" p[n] "$", "/", dir);
         count[dir]++; lines[dir] = lines[dir] $0 "\n"; kind[dir] = $1 }
       END { for (d in count)
               if (count[d] > 8) printf "%-8s %s (%d files)\n", kind[d], d, count[d]
               else printf "%s", lines[d] }' | sort -k2
}

printf '== modified package configs not in the repo\n'
pacman -Qii | awk '
  /^Backup Files/ { inb = 1; sub(/^Backup Files *: */, " ") }
  !/^Backup Files/ && !/^ / { inb = 0 }
  inb && /\[modified\]/ { print $(NF - 1) }
' | sort -u | while IFS= read -r file; do
  skip "$file" && continue
  tracked "$file" || printf 'modified %s\n' "$file"
done | collapse

printf '\n== unowned files not in the repo\n'
comm -23 \
  <(find /etc -xdev -type f 2>/dev/null | sort) \
  <(pacman -Qlq | grep '^/etc/' | sort -u) |
  while IFS= read -r file; do
    skip "$file" && continue
    tracked "$file" || printf 'unowned  %s\n' "$file"
  done | collapse

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  printf '\n(Some folders are root-only: run with sudo for the full list.)\n'
fi
