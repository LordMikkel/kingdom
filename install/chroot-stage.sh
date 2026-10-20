#!/usr/bin/env bash
set -euo pipefail

# Second half of the installer, run inside arch-chroot. Not meant to be run
# by hand. Expects PROFILE, HOSTNAME_NEW, USERNAME, TIMEZONE, KEYMAP and
# ROOT_UUID in the environment and the repo at /opt/dotfiles. The root is
# LUKS2 + btrfs.

: "${PROFILE:?}" "${HOSTNAME_NEW:?}" "${USERNAME:?}" "${TIMEZONE:?}"
: "${KEYMAP:?}" "${ROOT_UUID:?}"

home="/home/$USERNAME"
repo="$home/dotfiles"

# True when detect-drivers.sh picked an NVIDIA driver (not for a GPU so
# old that it is left to nouveau).
nvidia_driver() {
  "$repo/install/scripts/detect-drivers.sh" | grep -qE ' nvidia(-[0-9]+xx)?-utils$'
}

as_user() {
  # Without root's session variables: dconf would reach root's D-Bus.
  runuser -u "$USERNAME" -- env -u XDG_RUNTIME_DIR -u DBUS_SESSION_BUS_ADDRESS \
    HOME="$home" DOTFILES_DIR="$repo" DOTFILES_PROFILE="$PROFILE" \
    DOTFILES_YES=1 "$@"
}

# ---------------------------------------------------------------- base system

ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc
sed -i -e 's/^#\(en_US.UTF-8 UTF-8\)/\1/' -e 's/^#\(es_ES.UTF-8 UTF-8\)/\1/' \
  /etc/locale.gen
locale-gen
printf 'LANG=en_US.UTF-8\n' > /etc/locale.conf
printf 'KEYMAP=%s\n' "$KEYMAP" > /etc/vconsole.conf
printf '%s\n' "$HOSTNAME_NEW" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 $HOSTNAME_NEW.localdomain $HOSTNAME_NEW
EOF

useradd -m -G wheel -s /bin/zsh "$USERNAME"
chpasswd < /root/.pw
rm -f /root/.pw
passwd -l root

printf '%%wheel ALL=(ALL:ALL) ALL\n' > /etc/sudoers.d/10-wheel
# Package builds run as the user without a terminal to type a password in.
# Removed at the end of this script.
printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$USERNAME" > /etc/sudoers.d/99-installer
chmod 440 /etc/sudoers.d/10-wheel /etc/sudoers.d/99-installer
trap 'rm -f /etc/sudoers.d/99-installer' EXIT

mv /opt/dotfiles "$repo"
chown -R "$USERNAME:$USERNAME" "$repo"

# The configs name the user they were made by (/home/archer/..., firejail.users,
# systemctl -M archer@). Rewrite them for the new user name.
source_user="$(cat "$repo/install/source-user")"
if [ "$USERNAME" != "$source_user" ]; then
  grep -rlZw "$source_user" "$repo/home" "$repo/system" "$repo/gnome" 2>/dev/null |
    xargs -0 -r sed -i \
      -e "s|/home/$source_user\b|/home/$USERNAME|g" \
      -e "s/-M $source_user@/-M $USERNAME@/g" \
      -e "s/-o $source_user -g $source_user/-o $USERNAME -g $USERNAME/g" \
      -e "s/$source_user:$source_user/$USERNAME:$USERNAME/g" \
      -e "s/^$source_user\$/$USERNAME/" || true
fi

# ---------------------------------------------------------------- packages

packages_status=0
as_user "$repo/install/scripts/install-packages.sh" --yes \
  --only native --only aur --only flatpak --only tools || packages_status=$?

# Groups that only exist once their packages are installed.
for group in video input storage users libvirt vboxusers wireshark; do
  getent group "$group" >/dev/null && usermod -aG "$group" "$USERNAME"
done

# ---------------------------------------------------------------- /etc

# Copied after the packages so their default configs do not win (no .pacnew).
# fstab comes from genfstab and the USBGuard policy is generated for this
# hardware below.
while IFS= read -r snapshot; do
  live="${snapshot#$repo/system}"
  case "$live" in
    /etc/fstab|/etc/usbguard/rules.conf) continue ;;
  esac
  mode=644
  case "$live" in
    /etc/opensnitchd/rules/*|/etc/usbguard/*|/etc/ssh/sshd_config) mode=600 ;;
    /usr/local/bin/*) mode=755 ;;
  esac
  install -Dm"$mode" "$snapshot" "$live"
  printf 'installed %s\n' "$live"
done < <(find "$repo/system/etc" "$repo/system/usr/local" -type f 2>/dev/null | sort)

# Folders the copied configs expect but a fresh system lacks:
# - audit rules watching a path under /home: auditctl rejects a missing path
#   and then loads no rule at all. Created empty and private, for the data
#   restored later.
# - ReadWritePaths of service drop-ins: systemd refuses to start the service
#   when one is missing.
# (|| true: finding none of them is fine, e.g. the generic profile.)
grep -rhoE -- '-F dir=/home/[^ ]+' /etc/audit/rules.d 2>/dev/null |
  cut -d= -f2 | sort -u | while IFS= read -r dir; do
    install -d -m700 -o "$USERNAME" -g "$USERNAME" "$dir"
  done || true
grep -rhE '^ReadWritePaths=' /etc/systemd/system/*.d/*.conf 2>/dev/null |
  cut -d= -f2- | tr ' ' '\n' | sed 's/^-//' | grep '^/' | sort -u |
  while IFS= read -r dir; do
    [ -e "$dir" ] || install -d -m755 "$dir"
  done || true

# Compile the GDM dconf database from the copied keyfiles.
[ -d /etc/dconf/db/gdm.d ] && dconf update

# The copied pacman.conf may enable *-debug repos (they name their own
# server). Sync now, or every later install fails with "could not find
# database"; if they do not answer, leave them out.
if ! pacman -Sy; then
  sed -i -E '/^\[.*-debug\]/,/^(Include|Server)/ s/^/#/' /etc/pacman.conf
  printf 'Debug repos unreachable: commented out in /etc/pacman.conf\n'
  pacman -Sy
fi
# Packages from those repos (glibc-debug...) were skipped during the install,
# which ran without them.
if grep -q '^\[.*-debug\]' /etc/pacman.conf; then
  grep -- '-debug$' "$repo/packages/native.txt" |
    pacman -S --needed --noconfirm - || true
fi

# The copied GRUB config may come from an ext4 install: root on @ of btrfs.
sed -i -e 's/ *rootflags=subvol=[^ "]*//' \
  -e 's/rootfstype=[a-z0-9]*/rootfstype=btrfs rootflags=subvol=@/' /etc/default/grub
grep -qE '^MODULES=\(.*\bbtrfs\b' /etc/mkinitcpio.conf ||
  sed -i 's/^MODULES=(/MODULES=(btrfs /' /etc/mkinitcpio.conf

# Point GRUB at the new LUKS container.
sed -i "s/cryptdevice=UUID=[^:]*:/cryptdevice=UUID=$ROOT_UUID:/" /etc/default/grub
grep -q "cryptdevice=UUID=$ROOT_UUID:" /etc/default/grub || sed -i \
  "s|^GRUB_CMDLINE_LINUX=\"|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$ROOT_UUID:root:allow-discards root=/dev/mapper/root |" \
  /etc/default/grub

if ! nvidia_driver; then
  # No NVIDIA driver: drop its kernel options and initramfs modules, and let
  # nouveau load for an old NVIDIA GPU.
  sed -i -e 's/ *nvidia[-_]drm\.[a-z]*=[0-9]//g' /etc/default/grub
  sed -i -e 's/ *nvidia[a-z_]*//g' /etc/mkinitcpio.conf
  rm -f /etc/modprobe.d/nvidia.conf /etc/modprobe.d/nouveau.conf
fi

if [ -f /usr/bin/usbguard ]; then
  # Allow every USB device plugged in right now (keyboard included).
  usbguard generate-policy > /etc/usbguard/rules.conf
  chmod 600 /etc/usbguard/rules.conf
fi

# GRUB theme from the repo; /boot is vfat so it is copied, not linked.
if [ -d "$repo/boot/grub/themes" ]; then
  mkdir -p /boot/grub/themes
  cp -r "$repo/boot/grub/themes/." /boot/grub/themes/
fi

# ---------------------------------------------------------------- boot

mkinitcpio -P
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# ---------------------------------------------------------------- services, home

# Home first: some user units (voxtype-watchdog) live in the dotfiles.
as_user "$repo/scripts/install-home.sh"

# Own caelestia shell tweaks, rebuilt on top of the installed package.
as_user "$repo/install/scripts/install-caelestia-tweaks.sh" || packages_status=$?

# Zen profile ready before its first start: settings, mods, extensions.
if [ -d /var/lib/flatpak/app/app.zen_browser.zen ]; then
  as_user "$repo/install/scripts/install-zen.sh" || packages_status=$?
fi

# Rule sets of the opengrep-* aliases in .zshrc (too big for the repo).
if command -v opengrep >/dev/null; then
  as_user git clone -q --depth 1 https://github.com/semgrep/semgrep-rules \
    "$home/.config/opengrep/semgrep-rules" || true
fi
# swappy saves screenshots here (~/.config/swappy/config) but does not create it.
as_user mkdir -p "$home/Pictures/Screenshots"
as_user "$repo/install/scripts/install-claude-mcp.sh" || packages_status=$?

# GNOME settings and extensions (needs no session: it starts its own D-Bus).
if [ -x /usr/bin/gnome-shell ]; then
  as_user "$repo/scripts/install-gnome.sh" || packages_status=$?
fi

as_user "$repo/install/scripts/install-packages.sh" --yes --only services ||
  packages_status=$?

# Downloads and build trees from the install (several GB): packages come
# back from the mirrors and AUR builds from paru when needed.
rm -f /var/cache/pacman/pkg/*.pkg.tar.*
rm -rf "$home/.cache/paru/clone" "$home/.cache/go-build" "$home/.cargo/registry" \
  "$home/.npm/_cacache" "$home/.cache/yarn"

# ---------------------------------------------------------------- snapshots

# Last, once everything is installed: snap-pac snapshots every pacman
# transaction, and the install above makes dozens of them.
pacman -S --needed --noconfirm snapper
# snapper wants to create /.snapshots itself; the @snapshots subvolume is
# mounted there instead, so it survives rolling @ back.
umount /.snapshots
rmdir /.snapshots
snapper --no-dbus -c root create-config /
btrfs subvolume delete /.snapshots
mkdir /.snapshots
mount /.snapshots
chmod 750 /.snapshots
# Snapshots come from pacman only (snap-pac),
# the last 3 updates (6 snapshots) are kept, and a monthly scrub checks
# every block against its checksum.
snapper --no-dbus -c root set-config TIMELINE_CREATE=no NUMBER_LIMIT=6 \
  NUMBER_LIMIT_IMPORTANT=2
pacman -S --needed --noconfirm snap-pac
systemctl enable snapper-cleanup.timer btrfs-scrub@-.timer

# AIDE baseline of the finished system.
if command -v aide >/dev/null && [ -x /usr/local/bin/aide-update ]; then
  /usr/local/bin/aide-update || true
fi

printf '\n== Chroot stage finished\n'
if [ "$packages_status" -ne 0 ]; then
  printf 'Some packages or units failed: search "could not be installed" in\n'
  printf '/var/log/arch-install.log and install them after the first boot.\n'
fi
printf 'After the first login: restore your private data (SSH/GPG keys,\n'
printf 'documents) from your backup.\n'
