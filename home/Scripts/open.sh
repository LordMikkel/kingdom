#!/usr/bin/env bash
# Open anything with its default app, the current folder without arguments.
[ $# -eq 0 ] && set -- .
setsid -f gio open "$@" >/dev/null 2>&1
