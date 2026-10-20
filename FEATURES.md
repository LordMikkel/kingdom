# Features

What kingdom sets up, in detail. Back to the [README](README.md).

[Lynis](https://cisofy.com/lynis/) gives a full kingdom install a hardening
index around **80**.

## Disk

- The whole system is encrypted with **LUKS2**; only the 1G boot partition
  stays outside, as UEFI needs, and only root can read it. The passphrase is
  asked at every start.
- **btrfs** with separate subvolumes for `/`, `/home`, `/var/log`, the package
  cache, VM images and snapshots, all compressed with zstd.
- **snapper** takes a snapshot before and after every `pacman` update and
  keeps the last few, so a bad update can be rolled back.
- A monthly **scrub** checks every block against its checksum.
- **zram** for swap: half of the RAM, compressed with zstd. zswap is off.

## Network

- **DNS** goes through systemd-resolved, encrypted (DNS over TLS) to Quad9 and
  Mullvad, with DNSSEC. No plain DNS leaves the computer.
- **Wi-Fi MAC address** is random, both when scanning and when connecting.
- **nftables** firewall: nothing comes in unless it answers your own traffic.
  Open on purpose: LocalSend on the local network, DNS and DHCP for local VMs,
  and SSH (off by default) with at most 3 connections a minute.
- **OpenSnitch** asks before any program goes online. A few rules come ready
  for system services (DNS, time, updates, AUR, Flathub, ClamAV), each limited
  to one program and one port or server.
- **Proton VPN**, **Tor** and **proxychains** are installed.
- **Location** is off: geoclue never uses Wi-Fi networks or the modem, and
  only GNOME may ask it.

## Browser

- **Zen** is ready on its first start: uBlock Origin, Privacy Badger,
  Consent-O-Matic, Vimium and Multi-Account Containers, downloaded from
  Mozilla's store and checked against the hash it publishes, plus a few Zen
  mods (floating status bar, load bar).
- Zen runs as a Flatpak with no printers, no X11 and no access to
  NetworkManager, only the GPU.
- **Mullvad Browser** and **Tor Browser** for anonymous browsing.

## Kernel

- Boot options: `audit=1`, and the security modules
  `landlock,lockdown,yama,integrity,apparmor,bpf`. zswap off.
- `sysctl`: kernel logs and pointers hidden from users, unprivileged BPF off,
  SysRq off, protected links and files in `/tmp`, no core dumps of setuid
  programs; on the network, reverse-path filtering, SYN cookies, no ICMP
  redirects or source routing, IPv6 temporary addresses.

## Programs

- **hardened_malloc** (GrapheneOS's memory allocator) for the terminal and for
  Flatpak apps, except browsers and Electron apps, where it breaks.
- **Firejail** wraps every app it has a profile for.
- **Flatpak** permissions are tightened app by app:
  - browsers (Zen, Vivaldi, Mullvad): no printers, no X11, only the GPU;
  - Signal and Session: only the GPU;
  - Obsidian, LibreOffice, ImHex and VLC: no network.
- systemd services run with extra restrictions: NetworkManager, GDM, geoclue,
  OpenSnitch, Tor, udisks and more.
- **npm, yarn and bun** never run install scripts and pin exact versions; bun
  waits 3 days before installing a new release.
- **gdb** does not ask debug servers about your programs.

## Watch

- **AIDE** checks for files changed outside `pacman` before every update.
- **auditd** logs changes to accounts, sudo, mounts and kernel modules.
- **rkhunter** runs daily; **ClamAV** keeps its signatures up to date
  (`scanvirus` scans your home).
- AUR packages are checked against a list of known malicious ones before
  they are built.
- **usbguard** only allows the USB devices present at install time.
- Login: 5 wrong passwords lock the account for 5 minutes.

## Desktop

- **GNOME** and **Hyprland** with the **caelestia** shell; pick one at login.
- GNOME extensions: Vitals, AppIndicator, App Hider, IP Finder, Simple
  Taskbar, Removable Drive Menu, Status Area Spacing.
- caelestia with a few tweaks: hide the bar, hide the window title, a sturdier
  lock screen.
- Same look everywhere: Bibata cursor, Papirus icons, GTK and Qt themes, a
  GRUB theme and a wallpaper collection.

### Shortcuts

| Keys | Hyprland | GNOME |
|---|---|---|
| `Super` `T` | Terminal | Terminal |
| `Super` `B` | Zen | Zen |
| `Super` `C` | Zed | Zed |
| `Super` `E` | Files | Files |
| `Super` `A` | AI agent | AI agent |
| `Super` `O` | caelestia settings | GNOME settings |
| `Super` `.` | Emoji | Emoji |
| `Super` `V` | Clipboard history | |
| `Super` `J` | Obsidian | |
| `Super` `X` | LocalSend | |
| `Super` `Space` | Next keyboard layout | Next keyboard layout |
| `Super` `Backspace` | Close window | |
| `Ctrl` `Shift` `Space` | Voice dictation | Voice dictation |

## Kali lab

With the **Virtual machines** group:

```
kali setup
```

It downloads the official Kali image, checks it, and creates the VM. Then
`kali up`, `kali down` and `kali status`.

- Kali only reaches the internet **through Proton VPN**; with the VPN off it
  has no internet at all.
- It can never reach your computer or your local network.
- Its DNS goes through the VPN too.

## Optional groups

- **Development:** C and C++ (clang, gdb, valgrind, cppcheck, perf), Rust,
  Python (uv), Node and Bun, Flutter, Zed and VS Code, opengrep with the
  semgrep rules, Podman.
- **Hacking:** Metasploit, nmap, masscan, hashcat, john, hydra,
  aircrack-ng, sqlmap, nikto, wpscan, ZAP, Wireshark, nuclei, feroxbuster,
  binwalk, volatility, pwndbg, Cutter, ImHex and more.
- **Hardening and privacy:** the tools above (AppArmor, Firejail, OpenSnitch,
  usbguard, ClamAV, rkhunter, AIDE, lynis), Tor, Proton VPN, Mullvad Browser.
- **Virtual machines:** QEMU, virt-manager and the Kali lab.
- **AI tools:** Ollama, OpenCode, Claude Code, local voice dictation,
  ComfyUI, Upscayl.
- **Music:** REAPER and instruments.
- **Apps:** Zen, Vivaldi, Chromium, Obsidian, LibreOffice, Signal, Session,
  VLC, LocalSend, qBittorrent and more.
