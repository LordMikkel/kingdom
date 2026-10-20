#!/usr/bin/env bash
echo "--- 1. NATIVE BINARIES (pacman) ---"
pacman -Qe
echo ""
echo "--- 2. AUR PACKAGES (paru) ---"
pacman -Qm
echo ""
echo "--- 3. FLATPAK / SNAP ---"
flatpak list 2>/dev/null || echo "There is not Flatpaks."
snap list 2>/dev/null || echo "There is not Snaps."
echo ""
echo "=========================================="
