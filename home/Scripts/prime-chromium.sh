#!/usr/bin/env bash
# Chromium on the dedicated GPU, detached from the terminal.
setsid -f prime-run chromium --ozone-platform=x11 "$@" >/dev/null 2>&1
