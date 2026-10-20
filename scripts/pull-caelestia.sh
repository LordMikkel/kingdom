#!/usr/bin/env bash
set -euo pipefail

# Save the caelestia shell tweaks (~/.config/quickshell/caelestia, branch main
# on top of upstream) as patches in caelestia-tweaks/. The installer rebuilds
# the folder from them (install/scripts/install-caelestia-tweaks.sh).

repo="${DOTFILES_DIR:-$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")}"
src="$HOME/.config/quickshell/caelestia"
out="$repo/caelestia-tweaks"

if ! git -C "$src" rev-parse --verify -q upstream >/dev/null; then
  printf 'No tweaks repository in %s.\n' "$src" >&2
  exit 1
fi
if [ -n "$(git -C "$src" status --porcelain)" ]; then
  printf 'Uncommitted changes in %s: commit them first.\n' "$src" >&2
  exit 1
fi

mkdir -p "$out"
rm -f "$out"/*.patch
git -C "$src" format-patch -q upstream..main -o "$out"
printf 'Saved %s patches to %s.\n' "$(ls "$out"/*.patch | wc -l)" "$out"
