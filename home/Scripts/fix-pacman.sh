#!/usr/bin/env bash
# Rebuild the pacman mirrorlist with the fastest mirrors of some countries.
#   fix-pacman.sh ES,FR,DE
sudo reflector --country "${1:?usage: fix-pacman.sh <countries>}" \
  --protocol https --latest 20 --sort rate \
  --number 10 --save /etc/pacman.d/mirrorlist &&
  grep '^Server' /etc/pacman.d/mirrorlist
