# Shared by the installers (sourced, not run).
# They set PROFILE, then call preflight and run_installer with their question
# steps (ask_system, ask_disk...): it adds the last check and installs.
#
# The root is always LUKS2 + btrfs (subvolumes below),
# opened as /dev/mapper/root and booted by GRUB. Disk modes:
#   disk   erase a whole disk: EFI 1G + encrypted root
#   new    new partitions in the free space of a disk (EFI 1G + root of the
#          size you give); existing partitions are not touched
#   reuse  reinstall on an existing partition (and an existing /boot)
# Nothing is written before you confirm.

log=/tmp/arch-install.log

# Questions use dialog windows when it is there (the selector needs it too);
# without it they fall back to plain prompts. KINGDOM_TEXT=1 forces prompts.
# In windows, "Back" (the cancel button) goes one step back: the question
# helpers then return 1, and a step that finds a wrong answer returns 2 to be
# asked again (see run_steps).
use_dialog() { [ "${KINGDOM_TEXT:-0}" != 1 ] && [ -t 0 ] && command -v dialog >/dev/null; }

title="Arch install"

die() {
  if use_dialog; then clear; fi
  printf '\nError: %s\n' "$*" >&2
  exit 1
}

# note "text": shown above the next question.
notes=""
note() {
  if use_dialog; then notes+="$*"$'\n'; else printf '%s\n' "$*"; fi
}
# take_notes: move the pending notes into $noted (with a blank line after).
take_notes() {
  noted="${notes:+$notes$'\n'}"
  notes=""
}

# invalid "why": explain a wrong answer and ask the same question again.
invalid() { note "$1"; return 2; }

# Height that fits the text and the input or list below it.
fit() { echo $(( $(printf '%s\n' "$1" | wc -l) + $2 )); }

ask() {
  # ask VAR "Question" [default]; returns 1 on Back.
  local reply
  if use_dialog; then
    take_notes
    while true; do
      reply="$(dialog --stdout --title "$title" --cancel-label "Back" \
        --inputbox "$noted$2" "$(fit "$noted$2" 7)" 72 "${3:-}")" || return 1
      [ -n "$reply" ] && break
    done
  elif [ -n "${3:-}" ]; then
    read -rp "$2 [$3]: " reply
    reply="${reply:-$3}"
  else
    reply=""
    while [ -z "$reply" ]; do read -rp "$2: " reply; done
  fi
  printf -v "$1" '%s' "$reply"
}

ask_secret() {
  # ask_secret VAR "What" [minimum length]; returns 1 on Back.
  local a b min=${3:-1} problem
  while true; do
    if use_dialog; then
      take_notes
      a="$(dialog --stdout --title "$title" --cancel-label "Back" --insecure \
        --passwordbox "$noted$2" "$(fit "$noted$2" 7)" 64)" || return 1
      b="$(dialog --stdout --title "$title" --cancel-label "Back" --insecure \
        --passwordbox "$2 (again)" 0 64)" || return 1
    else
      read -rsp "$2: " a; printf '\n'
      read -rsp "$2 (again): " b; printf '\n'
    fi
    if [ "${#a}" -lt "$min" ]; then
      problem="Too short: use at least $min characters."
    elif [ "$a" != "$b" ]; then
      problem="The two do not match. Try again."
    else
      break
    fi
    note "$problem"
  done
  printf -v "$1" '%s' "$a"
}

# choose VAR "Question" default tag "description" [tag "description"]...
# Returns 1 on Back.
choose() {
  local var=$1 question=$2 default=$3 reply
  shift 3
  if use_dialog; then
    take_notes
    local rows=$(( $# / 2 > 10 ? 10 : $# / 2 ))
    reply="$(dialog --stdout --title "$title" --cancel-label "Back" \
      --default-item "$default" --menu "$noted$question" \
      "$(fit "$noted$question" $((rows + 7)))" 76 "$rows" "$@")" || return 1
  else
    take_notes
    printf '%s%s\n' "$noted" "$question"
    while [ "$#" -gt 1 ]; do printf '  %-14s %s\n' "$1" "$2"; shift 2; done
    read -rp "Choice [$default]: " reply
    reply="${reply:-$default}"
  fi
  printf -v "$var" '%s' "$reply"
}

# run_steps STEP...: run each step function in order. A step returns 0 to go
# on, 1 to go back one step, 2 to run again (after a wrong answer). Back from
# the first step returns 1, so steps can be nested; going back into a nested
# run_steps resumes at its last step ($going_back).
going_back=0
run_steps() {
  local steps=("$@") i=0 status
  [ "$going_back" = 1 ] && i=$(( ${#steps[@]} - 1 ))
  while [ "$i" -lt "${#steps[@]}" ]; do
    status=0
    "${steps[i]}" || status=$?
    going_back=0
    case "$status" in
      0) i=$((i + 1)) ;;
      2) ;;
      *)
        [ "$i" -eq 0 ] && { going_back=1; return 1; }
        i=$((i - 1))
        going_back=1
        ;;
    esac
  done
}

# Back from the very first question: leave, or stay.
quit_or_stay() {
  if use_dialog && dialog --title "$title" --yes-label "Quit" --no-label "Stay" \
    --yesno "Quit the installer? Nothing has been written." 0 0; then
    clear
    exit 0
  fi
}

# /dev/nvme0n1 + 2 -> /dev/nvme0n1p2, /dev/sda + 2 -> /dev/sda2
part_name() {
  case "$1" in
    *[0-9]) printf '%sp%s' "$1" "$2" ;;
    *) printf '%s%s' "$1" "$2" ;;
  esac
}

human() { numfmt --to=iec --suffix=B "$1"; }

preflight() {
  [ "${EUID:-$(id -u)}" -eq 0 ] || die "run as root from the Arch live ISO"
  [ -d /sys/firmware/efi ] || die "boot the ISO in UEFI mode (this installs GRUB for UEFI)"
  command -v pacstrap >/dev/null || die "pacstrap not found: run this from the Arch ISO"
  [ -f "$repo/packages/native.txt" ] || die "packages/native.txt missing in $repo"
  # HTTPS rather than ping: some networks (and QEMU user networking) drop ICMP.
  curl -fsI --max-time 15 https://archlinux.org >/dev/null 2>&1 ||
    die "no internet: connect first (iwctl station wlan0 connect <SSID>)"
  # The official Arch ISO has no dialog: fetch it into the live system.
  command -v dialog >/dev/null ||
    pacman -Sy --noconfirm --needed dialog >/dev/null 2>&1 || true
}

# ------------------------------------------------------------------ system

valid_hostname() { [[ "$1" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; }
valid_username() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && ! getent passwd "$1" >/dev/null
}
valid_timezone() {
  [[ "$1" =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$ ]] && [ -f "/usr/share/zoneinfo/$1" ]
}
valid_keymap() {
  [[ "$1" =~ ^[A-Za-z0-9_.-]+$ ]] &&
    [ -n "$(find /usr/share/kbd/keymaps -name "$1.map.gz" -print -quit 2>/dev/null)" ]
}

ask_hostname() {
  ask hostname "Computer name" "${hostname:-${default_hostname:-archlinux}}" || return 1
  valid_hostname "$hostname" ||
    invalid "Not valid: use lowercase letters, numbers and -, up to 63."
}
ask_username() {
  ask username "User name" "${username:-${default_user:-}}" || return 1
  valid_username "$username" ||
    invalid "Not valid: lowercase letters, numbers, - and _, starting with a letter."
}
ask_timezone() {
  ask timezone "Time zone, as Region/City" "${timezone:-${default_timezone:-UTC}}" || return 1
  valid_timezone "$timezone" ||
    invalid "Unknown time zone. Examples: Europe/London, America/Los_Angeles."
}
ask_keymap() {
  ask keymap "Keyboard layout (us, es, de, fr...)" "${keymap:-us}" || return 1
  valid_keymap "$keymap" || invalid "Unknown keyboard layout. Examples: us, es, de, fr, uk."
}
ask_user_pass() { ask_secret user_pass "Password for $username"; }
ask_luks_pass() { ask_secret luks_pass "Disk passphrase (asked at every start)" 8; }

ask_system() {
  use_dialog || printf '\n== System\n'
  run_steps ask_hostname ask_username ask_timezone ask_keymap ask_user_pass ask_luks_pass
}

# -------------------------------------------------------------------- disk

# Largest free block of a disk, in bytes.
largest_free() {
  sfdisk --list-free --bytes "$1" 2>/dev/null |
    awk '$1 ~ /^[0-9]+$/ && $4 ~ /^[0-9]+$/ { if ($4 > m) m = $4 } END { print m + 0 }'
}

# First partition numbers not in use on a disk.
free_partnums() {
  local used n=1 found=()
  used=" $(lsblk -nro PARTN "$1" 2>/dev/null | tr '\n' ' ') "
  while [ "${#found[@]}" -lt "$2" ]; do
    case "$used" in *" $n "*) ;; *) found+=("$n") ;; esac
    n=$((n + 1))
  done
  printf '%s\n' "${found[@]}"
}

# Menu items (path, description) for the disks, or for the partitions
# (optionally only those of one filesystem type).
disk_items() {
  lsblk -dnpo NAME,SIZE,TYPE,MODEL -e 7,11 |
    awk '$3 == "disk" { d = $2; for (i = 4; i <= NF; i++) d = d " " $i; print $1; print d }'
}
part_items() {
  lsblk -lnpo NAME,SIZE,TYPE,FSTYPE,LABEL -e 7,11 |
    awk -v fs="${1:-}" '$3 == "part" && (fs == "" || $4 == fs) {
      d = $2 "  " ($4 == "" ? "-" : $4); for (i = 5; i <= NF; i++) d = d "  " $i
      print $1; print d }'
}

ask_disk_mode() {
  use_dialog || lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS
  choose disk_mode "Where do you want to install it?" "${disk_mode:-new}" \
    new "Free space: next to what is already on the disk" \
    disk "Whole disk: erases everything on it" \
    reuse "One partition: replaces only that partition" || return 1
  case "$disk_mode" in
    new|disk|reuse) ;;
    *) invalid "Pick new, disk or reuse." ;;
  esac
}

# Step 2: the disk (disk, new) or the partition for the system (reuse).
ask_disk_target() {
  local items
  if [ "$disk_mode" = reuse ]; then
    mapfile -t items < <(part_items)
    [ "${#items[@]}" -gt 0 ] || die "no partitions found"
    choose root_part "Pick the partition for the system. It will be erased." \
      "${root_part:-${items[0]}}" "${items[@]}" || return 1
    [ "$(lsblk -no TYPE "$root_part" 2>/dev/null)" = part ] ||
      { invalid "$root_part is not a partition."; return; }
    local fs really
    fs="$(lsblk -no FSTYPE "$root_part" | head -1)"
    if [ "$fs" = ntfs ] || [ "$fs" = BitLocker ]; then
      note "Warning: $root_part ($fs) looks like Windows or your files."
      ask really "Type WINDOWS-IS-GONE to erase it anyway, or Back to pick another" || return 2
      [ "$really" = WINDOWS-IS-GONE ] || return 2
    fi
    return 0
  fi
  mapfile -t items < <(disk_items)
  [ "${#items[@]}" -gt 0 ] || die "no disks found"
  local question="Pick the disk with free space."
  [ "$disk_mode" = disk ] && question="Pick the disk. Everything on it will be erased."
  choose disk "$question" "${disk:-${items[0]}}" "${items[@]}" || return 1
  [ "$(lsblk -dno TYPE "$disk" 2>/dev/null)" = disk ] || invalid "$disk is not a whole disk."
}

# Step 3: what is left to decide for each mode.
ask_disk_layout() {
  # Only the reuse mode can keep an existing boot partition.
  format_boot=yes boot_note="" size_note=""
  case "$disk_mode" in
    disk)
      boot_part="$(part_name "$disk" 1)"
      root_part="$(part_name "$disk" 2)"
      ;;
    new) ask_root_size ;;
    reuse) ask_boot_part ;;
  esac
}

ask_root_size() {
  local free_bytes gib=$((1024 * 1024 * 1024)) top min=50 pick nums
  free_bytes="$(largest_free "$disk")"
  # Whole GiB left after the 1G boot partition, with room for alignment.
  top=$(( (free_bytes - gib - 16 * 1024 * 1024) / gib ))
  if [ "$top" -lt "$min" ]; then
    note "Not enough free space on $disk: $(human "$free_bytes") free, $((min + 1))G needed."
    return 1
  fi
  note "Free space on $disk: $(human "$free_bytes"). A 1G boot partition goes there too."
  ask pick "Size for the system in GB (at least $min, or max for all of it)" \
    "${root_gib:-max}" || return 1
  pick="${pick,,}" pick="${pick%gb}" pick="${pick%g}"
  if [ "$pick" = max ]; then
    pick=$top
  elif ! [[ "$pick" =~ ^[0-9]+$ ]] || [ "$((10#$pick))" -lt "$min" ]; then
    invalid "Not valid: a whole number of GB, at least $min, or max."
    return
  elif [ "$((10#$pick))" -gt "$top" ]; then
    invalid "Only $top GB fit: type $top or less, or max."
    return
  fi
  pick=$((10#$pick)) root_gib=$pick
  # Whole GiB, aligned by sgdisk. A rest under 5G is too small to use for
  # anything, so then the system takes the whole free block.
  if [ $((top - pick)) -lt 5 ]; then
    root_size=max root_label="all the free space, $(human $((free_bytes - gib)))"
  else
    root_size="${pick}G" root_label="${pick}G"
  fi
  mapfile -t nums < <(free_partnums "$disk" 2)
  boot_num="${nums[0]}" root_num="${nums[1]}"
  boot_part="$(part_name "$disk" "$boot_num")"
  root_part="$(part_name "$disk" "$root_num")"
}

ask_boot_part() {
  local items shared=no
  mapfile -t items < <(part_items vfat)
  [ "${#items[@]}" -gt 0 ] || die "no EFI (vfat) partition found"
  choose boot_part "Pick the boot (EFI) partition." "${boot_part:-${items[0]}}" \
    "${items[@]}" || return 1
  [ "$boot_part" != "$root_part" ] || { invalid "Boot and system must be different."; return; }
  # A boot partition shared with Windows must never be formatted.
  mkdir -p /tmp/boot-check
  mount -o ro "$boot_part" /tmp/boot-check
  if [ -d /tmp/boot-check/EFI/Microsoft ]; then shared=yes; fi
  umount /tmp/boot-check
  if [ "$shared" = yes ]; then
    format_boot=no
    boot_note="$boot_part has the Windows boot loader: it will not be formatted."
    use_dialog || printf '%s\n' "$boot_note"
  else
    choose format_boot "Format $boot_part? Only if nothing else uses it." yes \
      yes "Format it (only Arch will use it)" \
      no "Keep its files (shared with another system)" || return 1
  fi
  if [ "$(lsblk -bno SIZE "$boot_part")" -lt 500000000 ]; then
    size_note="$boot_part is under 500 MB: NVIDIA drivers may not fit."
    use_dialog || printf '%s\n' "$size_note"
  fi
  return 0
}

ask_disk() {
  use_dialog || printf '\n== Disk\n'
  run_steps ask_disk_mode ask_disk_target ask_disk_layout
}

# ------------------------------------------------------------------- check

# The plan, as text: drivers, then what is kept, created and erased.
plan_text() {
  printf 'Computer\n'
  printf '  Name        %s\n' "$hostname"
  printf '  User        %s\n' "$username"
  printf '  Time zone   %s\n' "$timezone"
  printf '  Keyboard    %s\n' "$keymap"
  printf '  Desktops    GNOME and Hyprland, picked at login\n'
  printf '\nDrivers\n'
  bash "$repo/install/scripts/detect-drivers.sh" --explain 2>&1 >/dev/null | sed 's/^/  /'
  printf '\nDisk\n'
  case "$disk_mode" in
    disk)
      printf '  Erase       %s, everything on it\n' "$disk"
      printf '  Create      %s boot (1G), %s system (encrypted)\n' "$boot_part" "$root_part"
      ;;
    new)
      printf '  Keep        everything already on %s\n' "$disk"
      printf '  Create      %s boot (1G), %s system (encrypted, %s)\n' \
        "$boot_part" "$root_part" "$root_label"
      ;;
    reuse)
      printf '  Erase       %s, for the system (encrypted)\n' "$root_part"
      printf '  Boot        %s (formatted: %s)\n' "$boot_part" "$format_boot"
      [ -z "${boot_note:-}" ] || printf '\n  %s\n' "$boot_note"
      [ -z "${size_note:-}" ] || printf '  %s\n' "$size_note"
      ;;
  esac
}

# Last check: the plan, then the word that starts the install. Back returns 1.
confirm() {
  # Only new partitions in free space: nothing existing is erased.
  local word=ERASE answer
  [ "$disk_mode" = new ] && word=INSTALL
  if use_dialog; then
    local plan
    take_notes
    # Section names in blue, as in the other windows.
    plan="$(plan_text | sed -E 's/^(Computer|Drivers|Disk)$/\\Zb\\Z4\1\\Zn/')"
    answer="$(dialog --stdout --colors --no-collapse --title "Ready to install" \
      --cancel-label "Back" --inputbox \
      "$plan"$'\n\n'"$noted""Nothing has been written yet. Type $word to start." \
      0 0)" || return 1
  else
    printf '\n== Plan\n'
    plan_text
    printf '\nNothing has been written yet.\n'
    ask answer "Type $word to start (or anything else to quit)" no
    [ "$answer" = "$word" ] || die "aborted"
  fi
  [ "$answer" = "$word" ] || invalid "Type $word exactly to start, or Back to change something."
  if use_dialog; then clear; fi
  return 0
}

# Every question, with Back working across them; then the install.
run_installer() {
  until run_steps "$@" confirm; do
    quit_or_stay
    going_back=0
  done
  install_system
}

make_partitions() {
  case "$disk_mode" in
    disk)
      wipefs -af "$disk"
      sgdisk --zap-all "$disk"
      sgdisk -n1:0:+1G -t1:ef00 -c1:EFI -n2:0:0 -t2:8309 -c2:cryptroot "$disk"
      ;;
    new)
      # Start 0 = start of the largest free block; end 0 = its end.
      local end=0
      [ "$root_size" = max ] || end="+$root_size"
      sgdisk -n "$boot_num:0:+1G" -t "$boot_num:ef00" -c "$boot_num:EFI-arch" "$disk"
      sgdisk -n "$root_num:0:$end" -t "$root_num:8309" -c "$root_num:cryptroot" "$disk"
      ;;
    reuse) return ;;
  esac
  partprobe "$disk"
  udevadm settle
}

install_system() {
  exec > >(tee -a "$log") 2>&1

  # ------------------------------------------------------------ disk
  make_partitions
  if [ "$format_boot" = yes ]; then mkfs.fat -F32 -n EFI "$boot_part"; fi

  wipefs -af "$root_part"
  printf '%s' "$luks_pass" |
    cryptsetup luksFormat --type luks2 --batch-mode --key-file - "$root_part"
  printf '%s' "$luks_pass" |
    cryptsetup open --allow-discards --key-file - "$root_part" root

  # Snapshots of @ leave out /home,
  # logs, VM images and the package cache. /home keeps relatime for AIDE.
  local subvols=(@ @home @snapshots @var_log @libvirt @pkg)
  local targets=(/ /home /.snapshots /var/log /var/lib/libvirt/images /var/cache/pacman/pkg)
  local atimes=(noatime relatime noatime noatime noatime noatime)
  local sv i
  mkfs.btrfs -f -L arch /dev/mapper/root
  mount /dev/mapper/root /mnt
  for sv in "${subvols[@]}"; do
    btrfs subvolume create "/mnt/$sv"
  done
  umount /mnt
  for i in "${!subvols[@]}"; do
    mount --mkdir -o "rw,compress=zstd:1,${atimes[i]},subvol=${subvols[i]}" \
      /dev/mapper/root "/mnt${targets[i]}"
  done
  chattr +C /mnt/var/lib/libvirt/images   # VM images: no copy-on-write
  mount --mkdir "$boot_part" /mnt/boot

  # ------------------------------------------------------------ base
  local ucode=intel-ucode
  if grep -q AuthenticAMD /proc/cpuinfo; then ucode=amd-ucode; fi

  # Same pacman.conf as the live system, minus the *-debug repos: they are
  # added back with the rest of /etc in the chroot stage.
  local pacman_conf=/tmp/pacman.install.conf
  awk '/^\[.*-debug\]/ { skip = 1; next } /^\[/ { skip = 0 } !skip' \
    "$repo/system/etc/pacman.conf" > "$pacman_conf"
  reflector --country Spain,France,Germany --protocol https --latest 15 \
    --sort rate --save /etc/pacman.d/mirrorlist 2>/dev/null || true

  # A slow mirror aborts the whole transaction: try again (downloads resume).
  # snapper and snap-pac come at the end of the chroot stage.
  local try
  for try in 1 2 3; do
    pacstrap -K -C "$pacman_conf" /mnt \
      base base-devel linux linux-headers linux-firmware "$ucode" \
      grub efibootmgr os-prober networkmanager sudo git stow zsh vim reflector \
      pciutils btrfs-progs compsize && break
    [ "$try" -lt 3 ] || die "pacstrap failed 3 times: check the network and mirrors"
    printf '\npacstrap failed, retrying (%s/3)...\n' "$((try + 1))"
    sleep 5
  done
  cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
  install -m644 "$pacman_conf" /mnt/etc/pacman.conf

  genfstab -U /mnt > /mnt/etc/fstab
  # Mount btrfs subvolumes by name only: a subvolid would pin the old @ after
  # a snapshot rollback.
  sed -i 's/subvolid=[0-9]*,\?//; s/,subvolid=[0-9]*//' /mnt/etc/fstab
  # /boot is FAT (no per-file permissions): only root may read it.
  sed -i '/[[:space:]]\/boot[[:space:]]/ s/fmask=[0-9]*,dmask=[0-9]*/fmask=0077,dmask=0077/' /mnt/etc/fstab

  mkdir -p /mnt/opt
  rm -rf /mnt/opt/dotfiles
  cp -a "$repo" /mnt/opt/dotfiles
  # A FAT USB drive or an ISO copy loses the executable bits: every file that
  # starts with #! gets it back (installer scripts, ~/Scripts, hooks).
  find /mnt/opt/dotfiles -path '*/.git' -prune -o -type f -print0 |
    while IFS= read -r -d '' f; do
      if [ "$(head -c2 "$f")" = '#!' ]; then chmod +x "$f"; fi
    done

  # Root stays locked: use sudo. The file is deleted by the chroot stage.
  printf '%s:%s\n' "$username" "$user_pass" > /mnt/root/.pw
  chmod 600 /mnt/root/.pw

  # ------------------------------------------------------------ chroot
  arch-chroot /mnt env \
    PROFILE="$PROFILE" HOSTNAME_NEW="$hostname" USERNAME="$username" \
    TIMEZONE="$timezone" KEYMAP="$keymap" \
    ROOT_UUID="$(blkid -s UUID -o value "$root_part")" \
    bash /opt/dotfiles/install/chroot-stage.sh

  cp "$log" /mnt/var/log/arch-install.log
  umount -R /mnt
  cryptsetup close root

  printf '\nDone. Log: /var/log/arch-install.log in the new system.\n'
  printf 'Remove the USB and reboot.\n'
}
