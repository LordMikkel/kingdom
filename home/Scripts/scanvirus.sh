#!/usr/bin/env bash
# Scan the home folder with ClamAV, running the daemon only for the scan.
list_file="/tmp/clamav_scan_list_$(date +%s).txt"
cleanup_done=0

cleanup() {
  trap - EXIT INT TERM
  [ "$cleanup_done" -eq 1 ] && return
  cleanup_done=1
  printf '\n❄️  Cleaning up...\n'
  sudo systemctl stop clamav-daemon.service clamav-daemon.socket 2>/dev/null
  [ -f "$list_file" ] && rm "$list_file"
  echo "✅ Scan finished. RAM released."
}

trap cleanup EXIT INT TERM

sudo -v
echo "🔥 Starting ClamAV engine..."
sudo systemctl start clamav-daemon

echo "⏳ Waiting for socket..."
while [ ! -S /run/clamav/clamd.ctl ]; do sleep 1; done
sleep 3

echo "🚀 Starting multithread scan on /home/$(whoami)..."
clamdscan --multiscan --fdpass --infected "/home/$(whoami)" 2>/dev/null
