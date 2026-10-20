#!/usr/bin/env bash
set -euo pipefail

expand_path() {
  local path="$1"
  path="${path/#\~/$HOME}"
  printf '%s\n' "$path"
}

print_dir_if_exists() {
  [ -d "$1" ] && printf '%s\n' "$1"
}

find_dirs() {
  local root="$1"
  local depth="$2"

  [ -d "$root" ] || return 0

  find "$root" \
    -maxdepth "$depth" \
    \( \
      -path '*/.git' -o \
      -path '*/.github' -o \
      -path '*/.gitlab' -o \
      -path '*/.circleci' -o \
      -path '*/.ci' -o \
      -path '*/ci' -o \
      -path '*/.zed' -o \
      -path '*/.vscode' -o \
      -path '*/node_modules' -o \
      -path '*/.cache' -o \
      -path '*/.serena' -o \
      -path '*/.local/share/Trash' -o \
      -path '*/target' -o \
      -path '*/dist' -o \
      -path '*/build' -o \
      -path '*/vendor' -o \
      -path '*/__pycache__' \
    \) -prune -o \
    -type d -print 2>/dev/null
}

find_root_dirs() {
  find / \
    -maxdepth 3 \
    \( \
      -path /proc -o \
      -path /sys -o \
      -path /dev -o \
      -path /run -o \
      -path /tmp -o \
      -path /var/cache -o \
      -path /var/lib -o \
      -path /var/tmp -o \
      -path /mnt -o \
      -path /media -o \
      -path /home/archer/.cache -o \
      -path /home/archer/.serena -o \
      -path /home/archer/.local/share/Trash \
    \) -prune -o \
    -type d -print 2>/dev/null
}

HISTORY_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/agent-ghostty/history"

# Previously chosen folders, most used first (ties: most recent first).
recent_dirs() {
  [ -f "$HISTORY_FILE" ] || return 0
  awk '{ n[$0]++; last[$0] = NR } END { for (d in n) print n[d], last[d], d }' \
    "$HISTORY_FILE" \
    | sort -k1,1nr -k2,2nr \
    | cut -d' ' -f3- \
    | while IFS= read -r dir; do print_dir_if_exists "$dir"; done
}

remember_dir() {
  mkdir -p "$(dirname "$HISTORY_FILE")"
  printf '%s\n' "$1" >> "$HISTORY_FILE"
  tail -n 500 "$HISTORY_FILE" > "$HISTORY_FILE.tmp" && mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
}

folder_list() {
  recent_dirs

  print_dir_if_exists "$HOME"
  print_dir_if_exists "$HOME/Projects"
  print_dir_if_exists "$HOME/Documents"
  print_dir_if_exists "$HOME/dotfiles"
  print_dir_if_exists "$HOME/42"
  print_dir_if_exists "$HOME/.config"

  find_dirs "$HOME/Projects" 1 | sort
  find_dirs "$HOME/Documents" 1 | sort
  find_dirs "$HOME/dotfiles" 1 | sort
  find_dirs "$HOME/42" 2 | sort

  {
    print_dir_if_exists "/"
    find_dirs "$HOME/Projects" 6
    find_dirs "$HOME/Documents" 6
    find_dirs "$HOME/dotfiles" 6
    find_dirs "$HOME/42" 6
    find_dirs "$HOME/.config" 1
    find_root_dirs
  } | sort
}

# In Hyprland the menus use fuzzel, the menu of the Caelestia shell (its
# colors follow the active scheme, ~/.config/fuzzel/fuzzel.ini); GNOME keeps
# wofi.
in_hyprland() {
  case ":${XDG_CURRENT_DESKTOP:-}:" in *:Hyprland:*) ;; *) return 1 ;; esac
  command -v fuzzel >/dev/null 2>&1
}

choose_folder() {
  local options prompt="${app_bin} >"
  options="$(folder_list | awk '!seen[$0]++' | sed "s#^$HOME#~#")"

  if in_hyprland; then
    printf '%s\n' "$options" | fuzzel --dmenu --prompt "󰉋  " \
      --placeholder "$app_name: choose a folder or type a path"
  elif command -v wofi >/dev/null 2>&1; then
    printf '%s\n' "$options" | wofi --dmenu --insensitive --matching fuzzy --prompt "$prompt" --location center --width 720 --height 420 --style /home/archer/.config/wofi/opencode.css
  elif command -v rofi >/dev/null 2>&1; then
    printf '%s\n' "$options" | env -u WAYLAND_DISPLAY GDK_BACKEND=x11 rofi -dmenu -i -p "$app_name folder" -mesg 'Choose a folder or type a path'
  else
    zenity --file-selection --directory --title="Choose folder for $app_name" --ok-label="Open $app_name" --filename="$HOME/"
  fi
}


ICONS="$HOME/Pictures/Icons"

choose_agent() {
  if in_hyprland; then
    printf '%s\0icon\x1f%s\n' \
      OpenCode "$ICONS/opencode-256.png" \
      ClaudeCode "$ICONS/claude-code.png" \
      | fuzzel --dmenu --only-match --prompt "󰚩  " --placeholder "Agent" \
          --lines 2 --width 30
    return
  fi
  printf '%s\n' \
    "img:$ICONS/opencode-256.png:text:OpenCode" \
    "img:$ICONS/claude-code.png:text:ClaudeCode" \
    | wofi --dmenu --allow-images --image-size 48 --insensitive \
        --prompt 'agent >' --location center --width 360 --height 190 \
        --hide-scroll --style /home/archer/.config/wofi/opencode.css
}

agent="${1:-}"
if [ -z "$agent" ]; then
  choice="$(choose_agent)" || exit 0
  case "$choice" in
    *Claude*) agent=claude ;;
    *OpenCode*) agent=opencode ;;
    *) exit 0 ;;
  esac
fi

case "$agent" in
  claude)
    app_name='Claude Code'; app_bin=claude
    app_class=com.anthropic.ClaudeCode; app_cmd=/usr/bin/claude ;;
  opencode)
    app_name='OpenCode'; app_bin=opencode
    app_class=com.opencode.OpenCode; app_cmd=/usr/bin/opencode ;;
  *)
    echo "usage: $0 [claude|opencode]" >&2; exit 2 ;;
esac

selected_dir="$(choose_folder)" || exit 0
[ -n "$selected_dir" ] || exit 0

selected_dir="$(expand_path "$selected_dir")"

if [ ! -d "$selected_dir" ]; then
  notify-send "$app_name" "Folder does not exist: $selected_dir" 2>/dev/null || true
  exit 1
fi

remember_dir "$(realpath "$selected_dir")"

exec /usr/bin/ghostty \
  --class="$app_class" \
  --gtk-single-instance=false \
  --working-directory="$selected_dir" \
  -e "$app_cmd"
