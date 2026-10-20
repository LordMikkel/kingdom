#!/usr/bin/env bash
# n8n in a container (~/.config/containers/systemd/n8n.container).
#   n8n.sh up      start it, open the browser when ready
#   n8n.sh down    stop it
#   n8n.sh update  download the latest image (used at the next start)
# During "up", Ctrl+C cancels the download, or only stops waiting once
# n8n is starting (it keeps starting in the background).
set -uo pipefail

url=http://127.0.0.1:5678
image=ghcr.io/n8n-io/n8n:latest

ready() { curl -sf -o /dev/null "$url"; }

# Detached from this terminal, so the browser's output doesn't land here.
open_browser() { setsid -f xdg-open "$url" >/dev/null 2>&1; }

up() {
  if ready; then
    echo "n8n already running: $url"
    open_browser
    return
  fi
  # Download here, with podman's own progress bars: inside systemd it shows
  # none and gives up after 5 minutes, too short behind a slow VPN.
  if ! podman image exists "$image"; then
    echo "Downloading the n8n image (first time only)..."
    podman pull "$image" || return 1
  fi
  systemctl --user start --no-block n8n.service || return 1
  printf "Starting n8n"
  trap 'echo; exit 130' INT
  until ready; do
    if systemctl --user is-failed -q n8n.service; then
      echo
      echo "n8n failed, last lines of its log:"
      journalctl --user -u n8n.service -n 15 -o cat --no-pager
      return 1
    fi
    printf "."
    sleep 1
  done
  echo
  echo "n8n ready: $url"
  open_browser
}

case "${1:-}" in
  up) up ;;
  down) systemctl --user stop n8n.service ;;
  update) podman pull "$image" ;;
  *) echo "usage: n8n up|down|update" >&2; exit 1 ;;
esac
