#!/usr/bin/env bash
set -euo pipefail

# Prepare the Zen browser profile before its first start, from browser/zen:
# settings (user.js), mods and shortcuts, and the extensions listed there,
# downloaded from addons.mozilla.org and checked against the hash it publishes.
# Zen (Flatpak) takes this profile as its own: the install id below is the
# same in every Flatpak install. Does nothing if Zen already has a profile.

repo="${DOTFILES_DIR:-$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../..")}"
src="$repo/browser/zen"
root="$HOME/.var/app/app.zen_browser.zen/.zen"
install_id=2953CB39A2589173
profile=kingdom.default-release

if [ -e "$root/profiles.ini" ]; then
  echo "zen: a profile already exists, left as it is"
  exit 0
fi

dir="$root/$profile"
mkdir -p "$dir/extensions"
cp "$src/user.js" "$src/zen-themes.json" "$src/zen-keyboard-shortcuts.json" "$dir/"
cp -r "$src/chrome" "$dir/chrome"
# Extensions placed in the profile start enabled, without a prompt.
printf 'user_pref("extensions.autoDisableScopes", 14);\n' >> "$dir/user.js"

# One addons.mozilla.org name per line; the id and hash come from its API.
install_extension() {
  local slug=$1 info id url hash tmp
  info="$(curl -fsSL "https://addons.mozilla.org/api/v5/addons/addon/$slug/")" || return 1
  read -r id url hash < <(python3 -c '
import json, sys
d = json.load(sys.stdin)
f = d["current_version"]["file"]
print(d["guid"], f["url"], f["hash"].split(":", 1)[1])' <<< "$info") || return 1
  tmp="$(mktemp)"
  curl -fsSL -o "$tmp" "$url" || { rm -f "$tmp"; return 1; }
  if [ "$(sha256sum "$tmp" | cut -d' ' -f1)" != "$hash" ]; then
    rm -f "$tmp"
    echo "zen: $slug does not match its published hash, skipped" >&2
    return 1
  fi
  mv "$tmp" "$dir/extensions/$id.xpi"
  echo "zen: $slug"
}

failed=0
for list in "$src/extensions.txt" "$src/extensions-personal.txt"; do
  [ -f "$list" ] || continue
  while read -r slug; do
    install_extension "$slug" || failed=1
  done < <(sed -e 's/#.*//' -e '/^\s*$/d' "$list")
done

cat > "$root/profiles.ini" <<EOF
[General]
StartWithLastProfile=1
Version=2

[Profile0]
Name=default-release
IsRelative=1
Path=$profile
Default=1

[Install$install_id]
Default=$profile
Locked=1
EOF
printf '[%s]\nDefault=%s\nLocked=1\n' "$install_id" "$profile" > "$root/installs.ini"
exit "$failed"
