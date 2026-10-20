#!/usr/bin/env bash
set -euo pipefail

# Rebuild ~/.config/quickshell/caelestia: the shell of the caelestia-shell
# package (branch "upstream") plus the patches of caelestia-tweaks/ (branch
# "main"). Quickshell loads it instead of /etc/xdg/quickshell/caelestia.
# Its TWEAKS.md and sync-upstream.sh come from the patches. If the patches
# do not apply to this caelestia-shell version, the stock shell is kept.

repo="${DOTFILES_DIR:-$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../..")}"
src=/etc/xdg/quickshell/caelestia
dest="$HOME/.config/quickshell/caelestia"

if [ ! -d "$src" ]; then
  printf 'caelestia-shell is not installed: nothing to do.\n'
  exit 0
fi
if [ -e "$dest" ]; then
  printf '%s already exists: left as it is.\n' "$dest"
  exit 0
fi

patches=("$repo"/caelestia-tweaks/*.patch)
if [ ! -e "${patches[0]}" ]; then
  printf 'No patches in %s/caelestia-tweaks.\n' "$repo"
  exit 0
fi

ver="$(pacman -Q caelestia-shell | cut -d' ' -f2)"
mkdir -p "$dest"
cp -a "$src/." "$dest/"
git() { command git -C "$dest" -c user.name=tweaks -c user.email=tweaks@localhost "$@"; }
git init -q -b upstream
git add -A
git commit -q -m "upstream: caelestia-shell $ver"
git checkout -q -b main
if git am -q --3way "${patches[@]}"; then
  printf 'caelestia tweaks applied (%s patches) on caelestia-shell %s.\n' \
    "${#patches[@]}" "$ver"
else
  git am --abort || true
  rm -rf "$dest"
  printf 'caelestia tweaks do not apply to caelestia-shell %s: stock shell kept.\n' "$ver" >&2
  exit 1
fi
