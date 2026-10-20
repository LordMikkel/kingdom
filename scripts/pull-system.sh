#!/usr/bin/env bash
set -euo pipefail

repo="${DOTFILES_DIR:-$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")}"

copy_file() {
  src="$1"
  dst="$repo/system$src"
  if [ ! -f "$src" ]; then
    printf 'skip missing %s\n' "$src"
    return
  fi
  if [ ! -r "$src" ]; then
    printf 'needs sudo %s\n' "$src"
    return
  fi
  mkdir -p "$(dirname "$dst")"
  install -m 0644 "$src" "$dst"
  if [ "${SUDO_UID:-}" ]; then
    chown "${SUDO_UID}:${SUDO_GID:-$SUDO_UID}" "$dst"
  fi
  printf 'pulled %s\n' "$src"
}

copy_dir_files() {
  src_dir="$1"
  if [ ! -d "$src_dir" ]; then
    printf 'skip missing %s\n' "$src_dir"
    return
  fi
  while IFS= read -r src; do
    copy_file "$src"
  done < <(find "$src_dir" -maxdepth 1 -type f | sort)
}

copy_matching_files() {
  src_dir="$1"
  name_pattern="$2"
  max_depth="$3"
  if [ ! -d "$src_dir" ]; then
    printf 'skip missing %s\n' "$src_dir"
    return
  fi
  if [ ! -r "$src_dir" ] || [ ! -x "$src_dir" ]; then
    printf 'needs sudo %s\n' "$src_dir"
    return
  fi
  while IFS= read -r src; do
    copy_file "$src"
  done < <(find "$src_dir" -maxdepth "$max_depth" -type f -name "$name_pattern" | sort)
}

copy_boot_file() {
  src="$1"
  dst="$repo/boot${src#/boot}"
  if [ ! -f "$src" ]; then
    printf 'skip missing %s\n' "$src"
    return
  fi
  mkdir -p "$(dirname "$dst")"
  install -m 0644 "$src" "$dst"
  if [ "${SUDO_UID:-}" ]; then
    chown "${SUDO_UID}:${SUDO_GID:-$SUDO_UID}" "$dst"
  fi
  printf 'pulled boot snapshot %s\n' "$src"
}

copy_boot_dir() {
  src="$1"
  dst="$repo/boot${src#/boot}"
  if [ ! -d "$src" ]; then
    printf 'skip missing %s\n' "$src"
    return
  fi
  rm -rf "$dst"
  mkdir -p "$(dirname "$dst")"
  # Copy content and mode only: keeping root ownership would make the repo
  # unwritable for the user on the next non-sudo pull.
  cp -r --preserve=mode,timestamps "$src" "$dst"
  if [ "${SUDO_UID:-}" ]; then
    chown -R "${SUDO_UID}:${SUDO_GID:-$SUDO_UID}" "$dst"
  fi
  printf 'pulled boot snapshot %s\n' "$src"
}

copy_file /etc/systemd/resolved.conf
copy_file /etc/default/grub
copy_file /etc/mkinitcpio.conf
copy_file /etc/fstab
copy_file /etc/pacman.conf
copy_file /etc/nftables.conf
copy_file /etc/systemd/system/ollama.service.d/override.conf
copy_file /etc/ssh/ssh_config
copy_file /etc/ssh/sshd_config
copy_file /etc/NetworkManager/NetworkManager.conf
copy_file /etc/iwd/main.conf
copy_file /etc/audit/auditd.conf
copy_file /etc/rkhunter.conf

copy_dir_files /etc/sysctl.d
copy_dir_files /etc/modprobe.d
copy_dir_files /etc/NetworkManager/conf.d
copy_dir_files /etc/clamav
copy_dir_files /etc/bluetooth
copy_matching_files /etc/security '*.conf' 1
copy_matching_files /etc/security/pwquality.conf.d '*.conf' 1
copy_matching_files /etc/ssh/ssh_config.d '*.conf' 1
copy_matching_files /etc/ssh/sshd_config.d '*.conf' 1
copy_matching_files /etc/audit/rules.d '*.rules' 1
copy_matching_files /etc/usbguard '*.conf' 1
copy_file /etc/usbguard/rules.conf
copy_matching_files /etc/systemd/system '*.conf' 3

# Found by audit-etc.sh: edited package configs and files made by hand.
copy_file /etc/systemd/zram-generator.conf
copy_file /etc/systemd/journald.conf
copy_file /etc/login.defs
copy_file /etc/pam.d/system-auth
copy_file /etc/profile
copy_file /etc/gdm/custom.conf
copy_file /etc/dconf/profile/gdm
copy_file /etc/mkinitcpio.d/linux.preset
copy_file /etc/libvirt/network.conf
copy_file /etc/proxychains.conf
copy_file /etc/tor/torrc
copy_file /etc/aur-malware/list.txt
copy_file /etc/X11/xorg.conf.d/00-keyboard.conf
copy_matching_files /etc/systemd/journald.conf.d '*.conf' 1
copy_matching_files /etc/systemd/system '*.mount' 1
copy_matching_files /etc/systemd/system '*.service' 1
copy_matching_files /etc/systemd/system '*.timer' 1
copy_matching_files /etc/makepkg.conf.d '*.conf' 1
copy_matching_files /etc/geoclue/conf.d '*.conf' 1
copy_file /etc/issue
copy_matching_files /etc/modules-load.d '*.conf' 1
copy_matching_files /etc/udev/rules.d '*.rules' 1
copy_matching_files /etc/pacman.d/hooks '*.hook' 1
copy_matching_files /etc/dconf/db/gdm.d '*' 1
copy_file /etc/firejail/firecfg.config
copy_file /etc/firejail/default.local
copy_file /etc/firejail/firejail.users
copy_file /etc/firejail/opencode.profile
copy_matching_files /etc/opensnitchd/rules '*.json' 1

# Own scripts and themes. The symlinks in /usr/local/bin are firejail's,
# made again by firecfg (pacman hook), so only regular files are kept.
while IFS= read -r src; do
  dst="$repo/system$src"
  mkdir -p "$(dirname "$dst")"
  install -m "$(stat -c %a "$src")" "$src" "$dst"
  if [ "${SUDO_UID:-}" ]; then
    chown "${SUDO_UID}:${SUDO_GID:-$SUDO_UID}" "$dst"
  fi
  printf 'pulled %s\n' "$src"
done < <(find /usr/local -xdev -path "*/.*" -prune -o -type f -print | sort)

copy_boot_file /boot/grub/grub.cfg
copy_boot_dir /boot/grub/themes/win-tux-dualboot-fullscreen

printf 'System snapshots updated under %s/system/etc.\n' "$repo"
