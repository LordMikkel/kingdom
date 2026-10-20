#!/usr/bin/env bash
set -euo pipefail

# Install the desktop, with the optional package groups picked by the user
# (install/generic/groups.txt).
#
#   1. Boot an Arch ISO in UEFI mode and connect to the internet.
#   2. Run:  bash install/install-generic.sh
#
# Desktops are always GNOME and Hyprland (caelestia), chosen at login in GDM.
# Steps: system questions, package selector, disk, last check, install.
# Nothing is written to disk before the last check.

repo="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
PROFILE=generic
# shellcheck source=lib/install-common.sh
source "$repo/install/lib/install-common.sh"
title="kingdom"
default_hostname=kingdom

groups_file="$repo/install/generic/groups.txt"
deselected="$repo/install/generic/deselected.txt"

# Not a generic copy yet: work on one.
if [ "$(cat "$repo/.install-profile" 2>/dev/null)" != generic ]; then
  copy=/tmp/generic-repo
  rm -rf "$copy"
  bash "$repo/install/scripts/export-generic.sh" "$copy" >/dev/null
  exec bash "$copy/install/install-generic.sh" "$@"
fi

# ---------------------------------------------------------------- groups.txt

# Names of a group (fixed groups are "=id").
group_packages() {
  awk -v g="$1" '/^\[/ { on = ($1 == "[" g "]"); next } on && NF && !/^#/' "$groups_file"
}
group_title() {
  awk -v g="$1" '$1 == "[" g "]" { $1 = ""; sub(/^ /, ""); print }' "$groups_file"
}
group_ids() {
  # group_ids fixed|optional
  awk -v kind="$1" '/^\[/ {
      id = substr($1, 2, length($1) - 2)
      fixed = (substr(id, 1, 1) == "=")
      if ((kind == "fixed") == fixed) print id
    }' "$groups_file"
}

# Everything the lists install that is in no group: the base.
base_packages() {
  local grouped excluded
  grouped="$(awk '/^\[/ || /^#/ || !NF { next } { print }' "$groups_file")"
  # Either file may be missing (the public repo has no this-machine.txt).
  excluded="$(sed -e 's/#.*//' -e '/^\s*$/d' "$repo/install/generic/exclude-packages.txt" \
    "$repo/install/this-machine.txt" 2>/dev/null || true)"
  cat "$repo/packages/native.txt" "$repo/packages/aur.txt" "$repo/packages/flatpak.txt" |
    grep -vxF -f <(printf '%s\n%s\n' "$grouped" "$excluded") |
    grep -vE '^(nvidia|opencl-nvidia|libva-nvidia|cuda|cudnn|intel-ucode|amd-ucode|intel-media-driver)' |
    sort
}

count() { grep -c . || true; }

# ------------------------------------------------------------------ screens

# Package names in 3 columns; names too long for one go on their own line.
columns() {
  awk '{ if (length($0) > 24) long[++nl] = $0; else short[++ns] = $0 }
    END {
      for (i = 1; i <= ns; i++) {
        printf "   %-25s", short[i]
        if (i % 3 == 0 || i == ns) printf "\n"
      }
      for (i = 1; i <= nl; i++) print "   " long[i]
    }' | sed 's/ *$//'
}

# Section names in light blue, group names in dark blue (dialog --colors
# codes; bold alone shows grey on the console).
section() { printf '\\Zb\\Z4%s\\Zn\n\n' "$1"; }
group() { printf '\\Z4%s\\Zn (%s)\n' "$1" "$2"; }

# Every package, by group: the "Full list" screen.
full_list() {
  local id
  section "Always installed"
  for id in $(group_ids fixed); do
    group "$(group_title "$id")" "$(group_packages "$id" | count)"
    group_packages "$id" | columns
    printf '\n'
  done
  group "Base: system, shell, fonts, sound, network, tools" "$(base_packages | count)"
  base_packages | columns
  printf '\n\\Z4Drivers\\Zn: the right ones for this computer.\n\n\n'
  section "Optional groups (you choose them next)"
  for id in $(group_ids optional); do
    group "$(group_title "$id")" "$(group_packages "$id" | count)"
    group_packages "$id" | columns
    printf '\n'
  done
}

# The first screen: what always comes and what is chosen next.
summary_text() {
  local id groups
  groups="$(for id in $(group_ids optional); do group_title "$id"; done |
    sed 's/:.*//' | paste -sd, | sed 's/,/, /g' | fold -s -w 56 | sed '2,$s/^/     /')"
  cat <<EOF
\\Zb\\Z4Always installed\\Zn

  Desktops   GNOME and Hyprland with caelestia
  Login      GDM, where you pick the desktop
  Base       system, shell, fonts, sound, network, tools
  Drivers    the right ones for this computer

\\Zb\\Z4You choose next\\Zn

  1. Optional groups:
     $groups
  2. The packages inside each one

\\Zb\\Z4Full list\\Zn shows every package, group by group.
EOF
}

# Continue: on. Full list: read it, then back here. Back: previous step.
show_summary() {
  local status=0
  dialog --colors --no-collapse --title "What you get" --yes-label "Continue" \
    --extra-button --extra-label "Full list" --no-label "Back" \
    --yesno "$(summary_text)" 22 72 || status=$?
  case "$status" in
    0) return 0 ;;
    3)
      dialog --colors --no-collapse --scrollbar --title "All packages (scroll, then Continue)" \
        --ok-label "Continue" --msgbox "$(full_list)" 32 86
      return 2
      ;;
    *) return 1 ;;
  esac
}

# The choices so far, kept when going back: ticked group ids, and for each
# group the packages unticked in it.
chosen="$(group_ids optional)"
declare -A left=()

pick_groups() {
  local id state reply args=()
  for id in $(group_ids optional); do
    state=off
    grep -qx "$id" <<< "$chosen" && state=on
    args+=("$id" "$(group_title "$id")" "$state")
  done
  reply="$(dialog --stdout --separate-output --title "Optional groups" --cancel-label "Back" \
    --checklist "Space: mark or unmark.  Enter: continue." 20 70 12 "${args[@]}")" ||
    return 1
  chosen="$reply"
}

# One group: all packages marked except those unticked before.
pick_group_packages() {
  local id=$1 pkg state keep args=()
  while IFS= read -r pkg; do
    state=on
    grep -qxF "$pkg" <<< "${left[$id]:-}" && state=off
    args+=("$pkg" "" "$state")
  done < <(group_packages "$id")
  keep="$(dialog --stdout --separate-output --title "$(group_title "$id")" \
    --cancel-label "Back" --checklist "All marked. Unmark what you do not need." \
    22 70 16 "${args[@]}")" || return 1
  left[$id]="$(group_packages "$id" | grep -vxF -f <(printf '%s\n' "$keep") || true)"
}

# Every ticked group in turn; Back from the first one goes to the groups.
pick_packages() {
  local ids k=0
  mapfile -t ids < <(grep . <<< "$chosen" || true)
  # No group ticked: nothing to ask, but Back still has to reach the groups.
  if [ "${#ids[@]}" -eq 0 ]; then
    [ "$going_back" = 1 ] && return 1
    return 0
  fi
  [ "$going_back" = 1 ] && k=$(( ${#ids[@]} - 1 ))
  while [ "$k" -lt "${#ids[@]}" ]; do
    if pick_group_packages "${ids[k]}"; then
      k=$((k + 1))
    elif [ "$k" -eq 0 ]; then
      return 1
    else
      k=$((k - 1))
    fi
  done
}

# Writes install/generic/deselected.txt, read by install-packages.sh.
write_deselected() {
  local id
  : > "$deselected"
  for id in $(group_ids optional); do
    if grep -qx "$id" <<< "$chosen"; then
      grep . <<< "${left[$id]:-}" >> "$deselected" || true
    else
      group_packages "$id" >> "$deselected"
    fi
  done
  note "Packages left out: $(count < "$deselected")"
}

select_packages() {
  if ! command -v dialog >/dev/null 2>&1; then
    : > "$deselected"
    printf '\n(dialog is missing: every optional group will be installed.)\n'
    return 0
  fi
  run_steps show_summary pick_groups pick_packages || return 1
  write_deselected
}

# --------------------------------------------------------------------- main

preflight
run_installer ask_system select_packages ask_disk
