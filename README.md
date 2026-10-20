# 🏰 kingdom

> Every machine is a realm that you need to defend.

**kingdom** is a configuration of linux based on privacy, performance, aesthetic,
hacking and development. You answer a few questions, pick what you want, and come
back to a system that boots into GNOME or Hyprland (with the caelestia shell),
encrypted, snapshotted and guarded from the first login.

## The realm

- **The soil** → GRUB
- **The King** → Arch Linux
- **The walls** → LUKS2
- **The chronicle** → btrfs
- **The granary** → zram
- **The gates** → nftables & usbguard
- **The watchtower** → AIDE & ClamAV
- **The main road** → GDM
- **The two courts** → GNOME & Hyprland with caelestia
- **The crusade** → a Kali lab, only through the VPN

Everything it does, in detail: [FEATURES.md](FEATURES.md).

## Install

You need a UEFI computer, internet and a backup of anything you care about.

### Option A: official Arch ISO

1. Download the [official Arch ISO](https://archlinux.org/download/):

   ```
   curl -LO https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso
   ```

2. Find your USB stick (for example `/dev/sdb`) and write the ISO to it.
   Everything on the stick is erased:

   ```
   lsblk
   ```
   ```
   sudo dd if=archlinux-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
   ```

3. Boot it and connect to Wi-Fi if needed (with a cable, skip this):

   ```
   iwctl station wlan0 connect "Network name"
   ```

4. Download kingdom:

   ```
   curl -L https://github.com/LordMikkel/kingdom/archive/refs/heads/main.tar.gz | tar xz
   ```

5. Start it:

   ```
   bash kingdom-main/install/install-generic.sh
   ```

### Option B: kingdom ISO

1. Download `kingdom-*.iso` from
   [Releases](https://github.com/LordMikkel/kingdom/releases):

   ```
   curl -LO https://github.com/LordMikkel/kingdom/releases/download/v0.0.1/kingdom-2026.10.20-x86_64.iso
   ```

2. Find your USB stick (for example `/dev/sdb`) and write the ISO to it.
   Everything on the stick is erased:

   ```
   lsblk
   ```
   ```
   sudo dd if=kingdom-2026.10.20-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
   ```

3. Boot it and connect to Wi-Fi if needed (with a cable, skip this):

   ```
   iwctl station wlan0 connect "Network name"
   ```

4. Start it:

   ```
   bash /root/dotfiles/install/install-generic.sh
   ```

The ISO already carries kingdom; it still downloads the packages, so it still
needs internet.

## Step by step

Every window has **Back**. A wrong answer is explained and asked again.
Nothing is written to disk until step 6.

1. **Your computer:** name, user, time zone, keyboard and passwords.

   <img src="install/.img/install-1-system.png" width="640">

2. **What you get.** *Full list* shows every package.

   <img src="install/.img/install-2-summary.png" width="640">

   <img src="install/.img/install-3-full-list.png" width="640">

3. **Optional groups.** `Space` marks or unmarks, `Enter` continues.

   <img src="install/.img/install-4-groups.png" width="640">

4. **Packages of each group.** Unmark what you do not need.

   <img src="install/.img/install-5-packages.png" width="640">

5. **Where to install:** free space next to Windows, a whole disk, or one
   partition. In free space, type the size in GB (50 or more, or `max`).

   <img src="install/.img/install-6-disk.png" width="640">

6. **Ready to install.** Type `INSTALL` (or `ERASE` when something is erased).
   It then works alone until it says *Done*: remove the USB and restart.

   <img src="install/.img/install-7-ready.png" width="640">

7. **GRUB.** Press `Enter`.

   <img src="install/.img/boot-1-grub.png" width="640">

8. **Disk passphrase.**

   <img src="install/.img/boot-2-passphrase.png" width="640">

9. **Log in.**

   <img src="install/.img/boot-3-gdm.png" width="640">

10. **Pick the desktop** with the gear, bottom right. It is remembered.

    <img src="install/.img/boot-4-session.png" width="640">

    Hyprland with caelestia

    <img src="install/.img/boot-5-caelestia.png" width="640">

    GNOME

    <img src="install/.img/boot-6-gnome.png" width="640">

## Credits

- Made by [LordMikkel](https://github.com/LordMikkel), built and tested
  together with Claude Code as a pair programmer.
- [Arch Linux](https://archlinux.org) and its wiki, the ground everything
  stands on.
- [caelestia](https://github.com/caelestia-dots) shell and CLI, with a few
  local tweaks in `caelestia-tweaks/`.
- [Hyprland](https://hyprland.org) and [GNOME](https://www.gnome.org).
