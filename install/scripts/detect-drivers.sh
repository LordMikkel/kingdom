#!/usr/bin/env bash
set -euo pipefail

# Pick the CPU microcode and GPU driver packages for the machine it runs on.
#   detect-drivers.sh [--explain] [--lspci FILE] [--cpu intel|amd]
# Prints one "repo PACKAGE" or "aur PACKAGE" line per package.
# --explain also prints what was found and why, on stderr.
# --lspci and --cpu fake the hardware (FILE holds `lspci -nn` output), to
# check what another machine would get.
#
# NVIDIA, by GPU generation (codename from lspci, else the PCI device id):
#   Turing and newer (TU, GA, AD, GH, GB...)  nvidia-open-dkms (repos)
#   Maxwell, Pascal, Volta (GM, GP, GV)       nvidia-580xx (AUR)
#   Kepler (GK)                               nvidia-470xx (AUR)
#   older                                     none: nouveau from mesa
# Intel GPU: vulkan-intel, intel-media-driver. AMD GPU: vulkan-radeon.
# NVIDIA next to another GPU (laptops): nvidia-prime.

explain=0
lspci_file=""
cpu=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --explain) explain=1 ;;
    --lspci) lspci_file="$2"; shift ;;
    --cpu) cpu="$2"; shift ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 1 ;;
  esac
  shift
done

say() { [ "$explain" -eq 0 ] || printf '%s\n' "$*" >&2; }
out() { printf '%s %s\n' "$1" "$2"; }

if [ -z "$cpu" ]; then
  cpu=intel
  grep -q AuthenticAMD /proc/cpuinfo && cpu=amd
fi
say "CPU: $cpu -> $cpu-ucode"
out repo "$cpu-ucode"

# Display controllers only: class 03xx.
if [ -n "$lspci_file" ]; then
  gpus="$(grep -E '\[03[0-9]{2}\]' "$lspci_file" || true)"
else
  gpus="$(lspci -nn | grep -E '\[03[0-9]{2}\]' || true)"
fi

nvidia=0 others=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  case "$line" in
    *"[8086:"*)
      others=1
      say "GPU: Intel -> vulkan-intel, intel-media-driver"
      out repo vulkan-intel
      out repo intel-media-driver
      ;;
    *"[1002:"*)
      others=1
      say "GPU: AMD -> vulkan-radeon"
      out repo vulkan-radeon
      ;;
    *"[10de:"*)
      nvidia=1
      chip="$(sed -nE 's/.*NVIDIA Corporation ([A-Z]{2}[0-9]{2,3}[A-Z]*).*/\1/p' <<< "$line")"
      code="${chip:0:2}"
      id="$(sed -nE 's/.*\[10de:([0-9a-f]{4})\].*/\1/p' <<< "$line")"
      id="${id:-0000}"
      gen=""
      case "$code" in
        TU|GA|AD|GH|GB) gen=open ;;
        GM|GP|GV) gen=580xx ;;
        GK) gen=470xx ;;
        G[FT]|NV) gen=none ;;
      esac
      # Unknown codename (a GPU newer than the PCI database): the device id
      # ranges follow the generations.
      if [ -z "$gen" ]; then
        if (( 16#$id >= 16#1e00 )); then gen=open
        elif (( 16#$id >= 16#1340 )); then gen=580xx
        elif (( 16#$id >= 16#0fc0 )); then gen=470xx
        else gen=none
        fi
      fi
      case "$gen" in
        open)
          say "GPU: NVIDIA ${chip:-?} [10de:$id], Turing or newer -> nvidia-open-dkms"
          for p in nvidia-open-dkms nvidia-utils nvidia-settings opencl-nvidia \
            libva-nvidia-driver; do out repo "$p"; done
          ;;
        580xx|470xx)
          say "GPU: NVIDIA ${chip:-?} [10de:$id], legacy -> nvidia-$gen (AUR)"
          for p in "nvidia-$gen-dkms" "nvidia-$gen-utils" "nvidia-$gen-settings" \
            "opencl-nvidia-$gen"; do out aur "$p"; done
          [ "$gen" = 580xx ] && out repo libva-nvidia-driver
          ;;
        none)
          say "GPU: NVIDIA ${chip:-?} [10de:$id], too old for the NVIDIA driver -> nouveau"
          nvidia=0
          ;;
      esac
      ;;
    *"[1af4:"*|*"[1234:"*|*"[15ad:"*|*"[80ee:"*)
      say "GPU: virtual (QEMU, VMware, VirtualBox) -> mesa only"
      ;;
    *) say "GPU: unknown, skipped: $line" ;;
  esac
done <<< "$gpus"

if [ "$nvidia" -eq 1 ] && [ "$others" -eq 1 ]; then
  say "Hybrid graphics -> nvidia-prime (prime-run)"
  out repo nvidia-prime
fi
[ -n "$gpus" ] || say "GPU: none found (virtual machine?) -> mesa only"
