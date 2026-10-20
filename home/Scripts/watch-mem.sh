#!/usr/bin/env bash
# Print a process's resident memory every 0.5s, to spot invisible leaks.
#   watch-mem.sh <process-name>
pid=$(pidof -s "${1:?usage: watch-mem.sh <process-name>}") || exit 1
while kill -0 "$pid" 2>/dev/null; do
  awk '/VmRSS/{print $2" KB"}' "/proc/$pid/status"
  sleep 0.5
done
