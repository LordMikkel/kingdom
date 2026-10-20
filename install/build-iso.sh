#!/usr/bin/env bash
set -euo pipefail

# Build a bootable Arch ISO that carries this repo and its installer.
#   build-iso.sh [OUT_DIR]
#
# The ISO is the official releng profile plus git, stow and dialog; packages
# are downloaded during the install, so the target machine needs internet.
# Boot it, connect, and run:  bash /root/dotfiles/install/install-generic.sh

repo="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
out=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -*) printf 'Unknown option: %s\n' "$1" >&2; exit 1 ;;
    *) out="$1" ;;
  esac
  shift
done

out="${out:-$PWD/iso-out}"
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  exec sudo "$(realpath "$0")" "$out"
fi
owner="${SUDO_UID:-0}:${SUDO_GID:-0}"

if [ ! -d /usr/share/archiso/configs/releng ]; then
  printf 'archiso is not installed: sudo pacman -S archiso\n' >&2
  exit 1
fi
case "$(realpath -m "$out")/" in
  "$repo"/*) printf 'Put the ISO outside the repo: %s\n' "$out" >&2; exit 1 ;;
esac

work="$(mktemp -d /var/tmp/arch-rebuild-iso.XXXXXX)"
trap 'rm -rf "$work"' EXIT
cp -r /usr/share/archiso/configs/releng "$work/profile"
dest="$work/profile/airootfs/root/dotfiles"

# A repo with the export script is cut down to its generic copy first; one
# without it (the public repo) is generic already and goes as is.
if [ -x "$repo/install/scripts/export-generic.sh" ]; then
  "$repo/install/scripts/export-generic.sh" "$dest"
else
  mkdir -p "$dest"
  if [ -d "$repo/.git" ]; then
    # Tracked and new files, not the ignored ones (backups, caches).
    git -c safe.directory="$repo" -C "$repo" ls-files -z --cached --others --exclude-standard |
      while IFS= read -r -d '' rel; do
        [ -e "$repo/$rel" ] || continue
        mkdir -p "$dest/$(dirname "$rel")"
        cp -a "$repo/$rel" "$dest/$rel"
      done
  else
    tar -C "$repo" -cf - . | tar -C "$dest" -xf -
  fi
fi
chown -R 0:0 "$dest"

# mkarchiso copies airootfs without file modes and applies only the ones in
# profiledef.sh: list every executable file of the repo there.
find "$dest" -path '*/.git' -prune -o -type f -perm -u+x -print |
  while IFS= read -r f; do
    printf 'file_permissions["%s"]="0:0:755"\n' "${f#"$work/profile/airootfs"}"
  done >> "$work/profile/profiledef.sh"

# dialog draws the package selector of install-generic.sh.
printf '%s\n' git stow dialog >> "$work/profile/packages.x86_64"

name=kingdom label=KINGDOM
cat >> "$work/profile/airootfs/etc/motd" <<EOF

$name ISO. Packages are downloaded: internet is needed.
  1. Connect to the internet:  cable works as is; Wi-Fi: iwctl station wlan0 connect <SSID>
  2. Install:                  bash /root/dotfiles/install/install-generic.sh

EOF

sed -i -e "s/^iso_name=.*/iso_name=\"$name\"/" \
  -e 's/^iso_label=.*/iso_label="'"$label"'_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"/' \
  "$work/profile/profiledef.sh"

mkdir -p "$out"
mkarchiso -v -w "$work/work" -o "$out" "$work/profile"
chown -R "$owner" "$out"
printf '\nISO written to %s\n' "$out"
