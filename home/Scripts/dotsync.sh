#!/usr/bin/env bash
# Commit and push every change in ~/dotfiles.
#   dotsync.sh [message]    the message defaults to "update"
set -e
cd ~/dotfiles
git add .
git commit -m "${1:-update}"
git push
