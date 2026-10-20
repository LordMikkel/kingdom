#!/usr/bin/env bash
# Restart voxtype when it gets stuck in its audio error loop.
#
# Sometimes the stream that plays its feedback beeps breaks and voxtype logs
# "alsa::poll() returned POLLERR" thousands of times a minute. voxtype and
# journald then use a whole CPU core each, the CPU overheats and throttles,
# and the desktop stutters. A restart fixes it.
# Run every minute by ~/.config/systemd/user/voxtype-watchdog.timer.

# A healthy voxtype logs no POLLERR at all; the loop logs ~20000 a minute.
limit=100

systemctl --user is-active --quiet voxtype || exit 0

errors=$(journalctl --user -u voxtype --since "-1min" -q -o cat \
    -g "POLLERR" 2>/dev/null | wc -l)
[ "$errors" -lt "$limit" ] && exit 0

# Do not cut a dictation short; the next run tries again.
[ "$(voxtype status 2>/dev/null)" = "recording" ] && exit 0

echo "voxtype logged $errors POLLERR errors in the last minute: restarting it"
systemctl --user restart voxtype
