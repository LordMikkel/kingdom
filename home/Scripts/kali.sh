#!/usr/bin/env bash
# Kali lab: a Kali VM in libvirt (qemu:///system) whose traffic can only leave
# through the VPN (/etc/nftables.conf, virbr-kali) and never reaches this
# computer or the LAN.
#   kali.sh setup   once: network, official Kali image (checked), the VM
#   kali.sh up      start it
#   kali.sh down    shut it down cleanly
#   kali.sh status  network and VM state
set -euo pipefail

conn=qemu:///system
here="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
dir=/var/lib/libvirt/images/kali-lab
disk="$dir/kali-work.qcow2"
mirror=https://cdimage.kali.org/current

v() { virsh -c "$conn" "$@"; }

setup_network() {
  if ! v net-info kali-vpn >/dev/null 2>&1; then
    v net-define "$here/kali/kali-vpn.xml" >/dev/null
    v net-autostart kali-vpn >/dev/null
  fi
  [[ "$(v net-info kali-vpn)" =~ Active:[[:space:]]+yes ]] || v net-start kali-vpn >/dev/null
  echo "network kali-vpn: ready"
}

# The official prebuilt QEMU image, checked against Kali's SHA256SUMS.
setup_disk() {
  if [ -f "$disk" ]; then
    echo "disk: $disk already there"
    return
  fi
  local name sums offline
  # A blocked or failed curl would end the script here without a word.
  offline="can't reach $mirror: check the internet, and allow curl if OpenSnitch asks"
  name="$(curl -fsL "$mirror/" | grep -oE 'kali-linux-[0-9.]+[a-z]?-qemu-amd64\.7z' | head -n 1)" ||
    true
  [ -n "$name" ] || { echo "no Kali QEMU image found. $offline" >&2; exit 1; }
  sudo install -d -o "$USER" -g "$USER" "$dir"
  echo "downloading $name (a few GB)"
  curl -fL --progress-bar -o "$dir/$name" "$mirror/$name"
  sums="$(curl -fsL "$mirror/SHA256SUMS")" || { echo "$offline" >&2; exit 1; }
  grep " $name\$" <<< "$sums" | (cd "$dir" && sha256sum -c --status) ||
    { echo "checksum mismatch: $dir/$name removed" >&2; rm -f "$dir/$name"; exit 1; }
  echo "checksum ok, extracting"
  7z x -y -o"$dir" "$dir/$name" >/dev/null
  mv "$dir"/kali-linux-*-qemu-amd64.qcow2 "$disk"
  rm -f "$dir/$name"
}

# Same settings as the original lab VM: no VMware port, no suspend, no HPET,
# UEFI without Secure Boot, entropy from the host.
setup_vm() {
  if v dominfo kali >/dev/null 2>&1; then
    echo "vm kali: already defined"
    return
  fi
  virt-install --connect "$conn" --print-xml --import --name kali \
    --osinfo debiantesting --memory 8192 --vcpus 4 --cpu host-passthrough \
    --boot uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=no,firmware.feature1.name=enrolled-keys,firmware.feature1.enabled=no \
    --features vmport.state=off \
    --pm suspend_to_mem.enabled=off,suspend_to_disk.enabled=off \
    --clock offset=utc,hpet_present=no \
    --disk "path=$disk,format=qcow2,bus=virtio" \
    --network network=kali-vpn,model=virtio,mac=52:54:00:fd:12:ab \
    --graphics spice --video virtio --rng /dev/urandom \
    --watchdog itco,action=reset > "$dir/kali.xml"
  v define "$dir/kali.xml" >/dev/null
  echo "vm kali: defined (login kali / kali; change it on first start)"
}

command -v virsh >/dev/null ||
  { echo "the Kali lab needs the Virtual machines group (libvirt, QEMU)" >&2; exit 1; }

case "${1:-}" in
  setup) setup_network; setup_disk; setup_vm ;;
  up) v start kali >/dev/null 2>&1 || true ;;
  down) v shutdown kali >/dev/null 2>&1 || true ;;
  status)
    v net-info kali-vpn 2>/dev/null | grep -E '^(Name|Active)' || echo "network kali-vpn: missing"
    v domstate kali 2>/dev/null || echo "vm kali: missing (kali.sh setup)"
    ;;
  *) echo "usage: kali setup|up|down|status" >&2; exit 1 ;;
esac
