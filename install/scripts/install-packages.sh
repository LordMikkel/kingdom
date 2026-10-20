#!/usr/bin/env bash
set -euo pipefail

# Install the packages and enable the units listed in packages/.
#   install-packages.sh [--yes] [--dry-run] [--profile personal|generic]
#                       [--only STEP]... [--lspci FILE] [--cpu intel|amd]
# STEP is one of: native, aur, flatpak, tools, services (default: all).
# tools: Python tools of uv-tools.txt and pip-user.txt (with uv tool, since
# pip --user is blocked on Arch) and pipx.txt (with pipx).
# --dry-run prints what each step would install or enable, and changes nothing.
# --lspci and --cpu fake the hardware (see detect-drivers.sh), for --dry-run.
#
# Drivers come from the hardware it runs on, not from the lists:
#   - microcode and GPU drivers in the lists are dropped and replaced with
#     what detect-drivers.sh picks for this CPU and GPU
#   - no usable NVIDIA GPU: CUDA and nvidia-* units are skipped too
#   - not the machine in install/machine-id: install/this-machine.txt
#     (tools for that exact laptop) is skipped
# The generic profile also drops what install/generic/exclude-*.txt lists.
#
# Packages that fail are listed at the end; the rest still get installed.

repo="${DOTFILES_DIR:-$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../..")}"
base="$repo/packages"
profile="${DOTFILES_PROFILE:-personal}"
assume_yes=0
dry_run=0
steps=()
detect_args=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes) assume_yes=1 ;;
    --dry-run) dry_run=1 ;;
    --profile) profile="$2"; shift ;;
    --only) steps+=("$2"); shift ;;
    --lspci|--cpu) detect_args+=("$1" "$2"); shift ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 1 ;;
  esac
  shift
done
[ "${#steps[@]}" -gt 0 ] || steps=(native aur flatpak tools services)

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  printf 'Run as your user, not root: makepkg refuses to run as root.\n' >&2
  exit 1
fi

case "$profile" in
  personal|generic) ;;
  *) printf 'Unknown profile: %s\n' "$profile" >&2; exit 1 ;;
esac

failed=()
replaced=()

# Print a list without comments and blank lines.
read_list() {
  [ -f "$1" ] || return 0
  sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$1"
}

# Packages detect-drivers.sh decides: whatever the lists say about them is
# what the old machine needed.
driver_re='^(intel-ucode|amd-ucode|intel-media-driver|vulkan-intel|vulkan-radeon|libva-nvidia-driver|nvidia-prime|nvidia(-[0-9]+xx)?(-open)?(-dkms)?|nvidia(-[0-9]+xx)?-(utils|settings)|opencl-nvidia(-[0-9]+xx)?)$'
# Need an NVIDIA driver to be useful.
nvidia_re='^(nvidia.*|.*-nvidia(-.*)?|cuda|cudnn)$'

drivers="$("$repo/install/scripts/detect-drivers.sh" "${detect_args[@]}")"
nvidia_driver=0
grep -qE ' nvidia(-[0-9]+xx)?-utils$' <<< "$drivers" && nvidia_driver=1
amd_cpu=0
grep -qx 'repo amd-ucode' <<< "$drivers" && amd_cpu=1
# Current CUDA needs a newer driver than the 470xx branch.
old_driver=0
grep -qx 'aur nvidia-470xx-utils' <<< "$drivers" && old_driver=1

# True on the machine the lists were made on (DMI vendor | product).
same_machine() {
  local id
  id="$(cat /sys/class/dmi/id/sys_vendor) | $(cat /sys/class/dmi/id/product_name)"
  [ "$(read_list "$repo/install/machine-id")" = "$id" ]
}

# Apply the profile and hardware rules to a list read on stdin.
filter() {
  local excludes=""
  if [ "$profile" = generic ]; then
    excludes="$(read_list "$repo/install/generic/exclude-$1.txt")"
    # Left out in the install-generic.sh selector.
    if [ "$1" = packages ]; then
      excludes+=$'\n'"$(read_list "$repo/install/generic/deselected.txt")"
    fi
  fi
  local machine_only=""
  same_machine || machine_only="$(read_list "$repo/install/this-machine.txt")"
  while IFS= read -r item; do
    if [ -n "$excludes" ] && grep -qxF "$item" <<< "$excludes"; then
      continue
    fi
    if [ -n "$machine_only" ] && grep -qxF "$item" <<< "$machine_only"; then
      continue
    fi
    if [ "$1" = packages ] && [[ "$item" =~ $driver_re ]]; then
      continue
    fi
    if [ "$nvidia_driver" -eq 0 ] && [[ "$item" =~ $nvidia_re ]]; then
      continue
    fi
    case "$item" in
      thermald|thermald.service) [ "$amd_cpu" -eq 1 ] && continue ;;
      cuda|cudnn) [ "$old_driver" -eq 1 ] && continue ;;
    esac
    printf '%s\n' "$item"
  done
}

# Final list for a step: the repo list filtered, plus the detected drivers.
wanted() {
  case "$1" in
    native) read_list "$base/native.txt" | filter packages
            sed -n 's/^repo //p' <<< "$drivers" ;;
    aur) read_list "$base/aur.txt" | filter packages
         sed -n 's/^aur //p' <<< "$drivers" ;;
    flatpak) read_list "$base/flatpak.txt" | filter packages ;;
    tools) read_list "$base/uv-tools.txt"; read_list "$base/pip-user.txt"
           read_list "$base/pipx.txt" ;;
    services) read_list "$base/services-system.txt" | filter services ;;
    user-services) read_list "$base/services-user.txt" | filter services ;;
  esac
}

install_native() {
  local wanted available missing pkg
  sudo pacman -Sy
  # A legacy NVIDIA driver from the AUR goes first: otherwise packages that
  # need nvidia-utils (libva-nvidia-driver, cuda) pull the current one from
  # the repos, and the AUR driver then conflicts with it.
  if grep -q '^aur ' <<< "$drivers"; then
    ensure_paru
    setup_keyserver
    while IFS= read -r pkg; do
      aur_install "$pkg"
    done < <(sed -n 's/^aur //p' <<< "$drivers")
  fi
  wanted="$(wanted native)"
  available="$(pacman -Sql | sort -u)"
  # A package that left the repos would make the whole transaction fail.
  # *-debug packages come from the debug repos, installed by chroot-stage.sh.
  missing="$(comm -23 <(sort -u <<< "$wanted") <(printf '%s\n' "$available") |
    grep -v -- '-debug$' || true)"
  if [ -n "$missing" ]; then
    printf 'not in the repos (skipped): %s\n' "$(tr '\n' ' ' <<< "$missing")"
    while IFS= read -r pkg; do failed+=("native:$pkg"); done <<< "$missing"
  fi
  local ok
  ok="$(comm -12 <(sort -u <<< "$wanted") <(printf '%s\n' "$available"))"
  # Two tries: a slow mirror aborts the whole transaction.
  sudo pacman -S --needed --noconfirm - <<< "$ok" ||
    sudo pacman -S --needed --noconfirm - <<< "$ok"
}

ensure_paru() {
  paru --version >/dev/null 2>&1 && return 0
  local tmp
  tmp="$(mktemp -d)"
  sudo pacman -S --needed --noconfirm base-devel git
  # Built from source, not paru-bin: the prebuilt binary links a fixed
  # libalpm.so version and stops starting as soon as pacman moves on.
  git clone --depth 1 https://aur.archlinux.org/paru.git "$tmp/paru"
  (cd "$tmp/paru" && makepkg -si --noconfirm)
  rm -rf "$tmp"
  paru --version >/dev/null
}

# The default keyserver lacks keys that some AUR sources are signed with.
setup_keyserver() {
  mkdir -p "$HOME/.gnupg"
  chmod 700 "$HOME/.gnupg"
  if [ ! -f "$HOME/.gnupg/dirmngr.conf" ]; then
    printf 'keyserver hkps://keyserver.ubuntu.com\n' > "$HOME/.gnupg/dirmngr.conf"
    gpgconf --kill dirmngr 2>/dev/null || true
  fi
}

# Fetch the PGP keys a PKGBUILD trusts (validpgpkeys) over plain HTTPS.
# gpg's own fetcher (dirmngr) fails in chroots and on some networks even
# when the web works; signatures are still checked against these keys.
import_aur_keys() {
  local key base
  # .SRCINFO has one "validpgpkeys = FPR" line per key: no bash to parse.
  base="$(curl -fsS --max-time 20 \
    "https://aur.archlinux.org/rpc/v5/info?arg[]=$1" |
    grep -oP '"PackageBase":"\K[^"]+' || printf '%s' "$1")"
  curl -fsS --max-time 20 \
    "https://aur.archlinux.org/cgit/aur.git/plain/.SRCINFO?h=$base" |
    sed -nE 's/^[[:space:]]*validpgpkeys = ([0-9A-Fa-f]{40})[[:space:]]*$/\1/p' |
    sort -u |
    while IFS= read -r key; do
      curl -fsS --max-time 20 \
        "https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x$key" |
        gpg --import 2>/dev/null && printf 'imported key %s\n' "$key"
    done
}

# Two tries, the second after importing the source keys: AUR downloads and
# keyservers fail now and then.
aur_install() {
  printf '\n==> AUR %s\n' "$1"
  # install/pkgbuilds/<name> replaces an AUR package that does not build.
  if [ -f "$repo/install/pkgbuilds/$1/PKGBUILD" ]; then
    local tmp
    tmp="$(mktemp -d)"
    cp -r "$repo/install/pkgbuilds/$1/." "$tmp/"
    (cd "$tmp" && makepkg -si --needed --noconfirm) || failed+=("pkgbuild:$1")
    rm -rf "$tmp"
    clean_build_caches
    return 0
  fi
  # Keys first: paru's own fetch goes through dirmngr, which hangs until it
  # times out in a chroot.
  import_aur_keys "$1" || true
  if ! paru -S --needed --noconfirm --skipreview "$1"; then
    if ! paru -S --needed --noconfirm --skipreview "$1"; then
      # A source package that stopped building often has a prebuilt -bin.
      if [[ "$1" != *-bin ]] && aur_exists "$1-bin" &&
        paru -S --needed --noconfirm --skipreview "$1-bin"; then
        printf 'installed %s-bin instead of %s (it did not build)\n' "$1" "$1"
        replaced+=("$1 -> $1-bin")
      else
        failed+=("aur:$1")
      fi
    fi
  fi
  clean_build_caches
}

aur_exists() {
  curl -fsS --max-time 20 "https://aur.archlinux.org/rpc/v5/info?arg[]=$1" |
    grep -q '"resultcount":1'
}

# Inside the installer only: drop each AUR build tree and the downloads once
# installed. Building everything in a row otherwise fills ~10 GB first.
clean_build_caches() {
  systemd-detect-virt --chroot >/dev/null 2>&1 || return 0
  rm -rf "$HOME/.cache/paru/clone" "$HOME/.cache/go-build" \
    "$HOME/.cargo/registry" "$HOME/.cargo/git" "$HOME/.npm/_cacache"
  sudo find /var/cache/pacman/pkg -maxdepth 1 -name '*.pkg.tar.*' -delete
}

install_aur() {
  ensure_paru
  setup_keyserver
  local pkg
  # One by one: a broken AUR package must not block the others.
  while IFS= read -r pkg; do
    aur_install "$pkg"
  done < <(wanted aur)
}

install_flatpak() {
  command -v flatpak >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm flatpak
  sudo flatpak remote-add --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
  local app
  # Two tries: big pulls from flathub fail now and then on a network hiccup.
  while IFS= read -r app; do
    sudo flatpak install --system --noninteractive flathub "$app" ||
      sudo flatpak install --system --noninteractive flathub "$app" ||
      failed+=("flatpak:$app")
  done < <(wanted flatpak)
}

# unit_file_exists UNIT DIR...: also for template instances (getty@tty1).
unit_file_exists() {
  local unit=$1 d
  shift
  for d in "$@"; do
    [ -e "$d/$unit" ] && return 0
    case "$unit" in *@*.*) [ -e "$d/${unit%%@*}@.${unit##*.}" ] && return 0 ;; esac
  done
  return 1
}

# unit_program_exists UNIT DIR...: false when the unit's ExecStart program
# is missing (its package was left out, e.g. ollama in a home unit).
unit_program_exists() {
  local unit=$1 d exe
  shift
  for d in "$@"; do
    [ -f "$d/$unit" ] || continue
    exe="$(sed -n 's/^ExecStart=[-@!+:]*\([^ ]*\).*/\1/p' "$d/$unit" | head -n 1)"
    case "$exe" in /*) [ -x "$exe" ]; return ;; esac
    return 0
  done
  return 0
}

install_tools() {
  local tool
  if command -v uv >/dev/null 2>&1; then
    while IFS= read -r tool; do
      uv tool install "$tool" >/dev/null || failed+=("tool:$tool")
    done < <(read_list "$base/uv-tools.txt"; read_list "$base/pip-user.txt")
  fi
  if command -v pipx >/dev/null 2>&1; then
    while IFS= read -r tool; do
      pipx install "$tool" >/dev/null || failed+=("pipx:$tool")
    done < <(read_list "$base/pipx.txt")
  fi
}

enable_services() {
  local unit user_flags=(--user)
  # Inside the installer's chroot there is no user manager to talk to, so
  # work on the unit files directly.
  if systemd-detect-virt --chroot >/dev/null 2>&1; then
    user_flags+=(--root=/)
  fi
  # A unit whose package was left out (generic selector) has no unit file:
  # skip it instead of reporting a failure.
  local dirs=(/etc/systemd/system /usr/lib/systemd/system)
  local udirs=("$HOME/.config/systemd/user" /etc/systemd/user /usr/lib/systemd/user)
  while IFS= read -r unit; do
    unit_file_exists "$unit" "${dirs[@]}" || continue
    unit_program_exists "$unit" "${dirs[@]}" || continue
    sudo systemctl enable "$unit" >/dev/null 2>&1 || failed+=("unit:$unit")
  done < <(wanted services)
  while IFS= read -r unit; do
    unit_file_exists "$unit" "${udirs[@]}" || continue
    unit_program_exists "$unit" "${udirs[@]}" || continue
    systemctl "${user_flags[@]}" enable "$unit" >/dev/null 2>&1 ||
      failed+=("user-unit:$unit")
  done < <(wanted user-services)
}

for list in native.txt aur.txt; do
  if [ ! -f "$base/$list" ]; then
    printf 'Missing %s: run pull-packages.sh first.\n' "$base/$list" >&2
    exit 1
  fi
done

printf 'Profile: %s   steps: %s\n' "$profile" "${steps[*]}"
"$repo/install/scripts/detect-drivers.sh" --explain "${detect_args[@]}" >/dev/null
if [ -f "$repo/install/machine-id" ]; then
  if same_machine; then
    printf 'Machine: same as install/machine-id\n'
  else
    printf 'Machine: not the one in install/machine-id (this-machine.txt skipped)\n'
  fi
fi
if [ "$dry_run" -eq 1 ]; then
  for step in "${steps[@]}"; do
    lists=("$step")
    [ "$step" = services ] && lists=(services user-services)
    for list in "${lists[@]}"; do
      printf '\n== %s\n' "$list"
      wanted "$list" | tr '\n' ' '
      printf '\n'
    done
  done
  exit 0
fi
if [ "$assume_yes" -eq 0 ]; then
  printf 'Install packages and enable units? Type YES to continue: '
  read -r answer
  if [ "$answer" != "YES" ]; then
    printf 'Aborted.\n'
    exit 1
  fi
fi

for step in "${steps[@]}"; do
  case "$step" in
    native) install_native ;;
    aur) install_aur ;;
    flatpak) install_flatpak ;;
    tools) install_tools ;;
    services) enable_services ;;
    *) printf 'Unknown step: %s\n' "$step" >&2; exit 1 ;;
  esac
done

if [ "${#replaced[@]}" -gt 0 ]; then
  printf '\nInstalled the prebuilt -bin package instead (the source did not build):\n'
  printf '  %s\n' "${replaced[@]}"
fi
if [ "${#failed[@]}" -gt 0 ]; then
  printf '\nThese could not be installed or enabled:\n'
  printf '  %s\n' "${failed[@]}"
  exit 2
fi
printf '\nAll packages installed and units enabled.\n'
