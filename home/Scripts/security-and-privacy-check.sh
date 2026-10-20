#!/usr/bin/env bash

# ==========================================================
#  ARCH SECURITY & PRIVACY AUDIT - ELITE QUICK CHECK
#  Read-only checks for Arch Linux laptops/workstations.
# ==========================================================

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BLUE='\033[0;34m'
NC='\033[0m'

OK_COUNT=0
INFO_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
CRIT_COUNT=0
LOW_COUNT=0
ONLINE=0
HAVE_SUDO=0
SUDO=""
FINDINGS=()

usage() {
    printf 'Usage: %s [--online] [--help]\n' "${0##*/}"
    printf '  --online   Enable external network checks: public IP and Tor exit test.\n'
    printf '  --help     Show this help.\n'
}

for arg in "$@"; do
    case "$arg" in
        --online) ONLINE=1 ;;
        --help|-h) usage; exit 0 ;;
        *) printf '%b[ERROR]%b Unknown argument: %s\n' "$RED" "$NC" "$arg"; usage; exit 2 ;;
    esac
done

ok() { printf '%b[OK]%b %s\n' "$GREEN" "$NC" "$*"; OK_COUNT=$((OK_COUNT + 1)); }
info() { printf '%b[INFO]%b %s\n' "$BLUE" "$NC" "$*"; INFO_COUNT=$((INFO_COUNT + 1)); }
warn() { printf '%b[WARN]%b %s\n' "$YELLOW" "$NC" "$*"; WARN_COUNT=$((WARN_COUNT + 1)); FINDINGS+=("WARN: $*"); }
fail() { printf '%b[FAIL]%b %s\n' "$RED" "$NC" "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); FINDINGS+=("FAIL: $*"); }
crit() { printf '%b[CRITICAL]%b %s\n' "$RED" "$NC" "$*"; CRIT_COUNT=$((CRIT_COUNT + 1)); FINDINGS+=("CRITICAL: $*"); }
low() { printf '%b[LOW]%b %s\n' "$CYAN" "$NC" "$*"; LOW_COUNT=$((LOW_COUNT + 1)); }
section() { printf '\n%b=== %s ===%b\n' "$WHITE" "$*" "$NC"; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }
is_active() { systemctl is-active --quiet "$1" 2>/dev/null; }
is_enabled() { systemctl is-enabled --quiet "$1" 2>/dev/null; }

run_priv() {
    if [[ "$HAVE_SUDO" -eq 1 ]]; then
        sudo "$@"
    else
        "$@"
    fi
}

sysctl_get() {
    sysctl -n "$1" 2>/dev/null || true
}

check_sysctl_eq() {
    local key="$1" expected="$2" severity="$3" label="$4" value
    value="$(sysctl_get "$key")"
    if [[ "$value" == "$expected" ]]; then
        ok "$label: $key=$value"
    elif [[ -z "$value" ]]; then
        warn "$label: $key unavailable"
    elif [[ "$severity" == "critical" ]]; then
        crit "$label: $key=$value, expected $expected"
    elif [[ "$severity" == "fail" ]]; then
        fail "$label: $key=$value, expected $expected"
    else
        warn "$label: $key=$value, expected $expected"
    fi
}

file_perm() {
    local path="$1"
    stat -c '%a %U:%G' "$path" 2>/dev/null || true
}

check_file_perm_any() {
    local path="$1" owners="$2" modes="$3" severity="$4" current mode owner
    if [[ ! -e "$path" ]]; then
        warn "Missing expected file: $path"
        return
    fi
    current="$(file_perm "$path")"
    mode="${current%% *}"
    owner="${current#* }"
    if [[ " $owners " == *" $owner "* && " $modes " == *" $mode "* ]]; then
        ok "Permissions: $path is $mode $owner"
    elif [[ "$severity" == "critical" ]]; then
        crit "Permissions: $path is $mode $owner, expected mode [$modes], owner [$owners]"
    elif [[ "$severity" == "fail" ]]; then
        fail "Permissions: $path is $mode $owner, expected mode [$modes], owner [$owners]"
    else
        warn "Permissions: $path is $mode $owner, expected mode [$modes], owner [$owners]"
    fi
}

has_nft_rule() {
    local pattern="$1"
    [[ -n "${NFT_RULESET:-}" && "$NFT_RULESET" =~ $pattern ]]
}

nft_chain_has_policy_drop() {
    local chain="$1" source="$2"
    printf '%s\n' "$source" | awk -v chain="$chain" '
        $0 ~ "chain " chain "[[:space:]]*\\{" {inside=1}
        inside && /policy drop/ {found=1}
        inside && /^ *}/ {inside=0}
        END {exit !found}
    '
}

nft_source_has() {
    local pattern="$1" source="$2"
    printf '%s\n' "$source" | grep -Eq "$pattern"
}

sshd_effective() {
    if has_cmd sshd; then
        local sshd_t_output sshd_t_status
        sshd_t_output="$(sshd -T 2>&1)"
        sshd_t_status=$?
        if [[ "$sshd_t_status" -eq 0 ]]; then
            printf '%s\n' "$sshd_t_output"
        else
            [[ "$sshd_t_output" == *"no hostkeys available"* ]] && SSHD_HOSTKEY_FALLBACK=1
            awk '
                /^[[:space:]]*#/ || /^[[:space:]]*$/ {next}
                {key=tolower($1); print key, $2}
            ' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null || true
        fi
    fi
}

check_sshd_key() {
    local config="$1" key="$2" expected="$3" severity="$4" current
    current="$(printf '%s\n' "$config" | awk -v k="$key" '$1 == k {print $2; exit}')"
    if [[ "$current" == "$expected" ]]; then
        ok "SSH: $key=$current"
    elif [[ -z "$current" ]]; then
        if [[ "${SSHD_HOSTKEY_FALLBACK:-0}" -eq 1 ]]; then
            info "SSH: $key not explicit in config; effective defaults unavailable because host keys are missing"
        else
            warn "SSH: $key not visible in effective config"
        fi
    elif [[ "$severity" == "critical" ]]; then
        crit "SSH: $key=$current, expected $expected"
    elif [[ "$severity" == "fail" ]]; then
        fail "SSH: $key=$current, expected $expected"
    else
        warn "SSH: $key=$current, expected $expected"
    fi
}

check_pkg_installed() {
    local pkg="$1" label="$2"
    if has_cmd pacman && pacman -Qq "$pkg" >/dev/null 2>&1; then
        ok "$label installed ($pkg)"
    else
        warn "$label not installed ($pkg)"
    fi
}

printf '%bARCH SECURITY & PRIVACY AUDIT%b\n' "$WHITE" "$NC"
printf 'Target: Arch Linux laptop/workstation | Mode: %s\n' "$([[ "$ONLINE" -eq 1 ]] && printf 'online' || printf 'offline-safe')"
printf '%s\n' '--------------------------------------------------------'

if sudo -v; then
    HAVE_SUDO=1
    SUDO="sudo"
    ok "Sudo privileges confirmed for complete read-only audit"
else
    printf '%b[ERROR]%b Sudo is required. Aborting to avoid incomplete or misleading results.\n' "$RED" "$NC" >&2
    exit 1
fi

section "System Fingerprint"
HOSTNAME_VALUE="$(hostname 2>/dev/null || true)"
KERNEL_VALUE="$(uname -r 2>/dev/null || true)"
OS_PRETTY="unknown"
if [[ -r /etc/os-release ]]; then
    OS_PRETTY="$(awk -F= '$1 == "PRETTY_NAME" {gsub(/"/, "", $2); print $2}' /etc/os-release)"
fi
info "Hostname: ${HOSTNAME_VALUE:-unknown}"
info "OS: $OS_PRETTY"
info "Kernel: ${KERNEL_VALUE:-unknown}"
if [[ "$OS_PRETTY" == *Arch* ]]; then ok "Distribution matches Arch Linux profile"; else warn "Distribution is not clearly Arch Linux"; fi

section "Physical & Boot Security"
if lsblk -o TYPE,FSTYPE 2>/dev/null | awk '$1 == "crypt" || $2 ~ /^crypto_LUKS/ {found=1} END {exit !found}'; then
    ok "Disk encryption: LUKS/crypt volume detected"
else
    crit "Disk encryption: no LUKS/crypt volume detected"
fi

if has_cmd mokutil; then
    SB_STATE="$(mokutil --sb-state 2>/dev/null || true)"
    if [[ "$SB_STATE" == *enabled* || "$SB_STATE" == *Enabled* ]]; then
        ok "Secure Boot: enabled"
    else
        warn "Secure Boot: disabled or unavailable (${SB_STATE:-unknown})"
    fi
else
    warn "Secure Boot: mokutil not installed"
fi

CMDLINE="$(tr '\0' ' ' </proc/cmdline 2>/dev/null || true)"
[[ "$CMDLINE" == *"init=/bin/bash"* || "$CMDLINE" == *" init="* ]] && crit "Kernel cmdline: dangerous init= parameter present" || ok "Kernel cmdline: no dangerous init= override"
[[ "$CMDLINE" == *"selinux=0"* ]] && crit "Kernel cmdline: selinux=0 present" || ok "Kernel cmdline: selinux=0 absent"
[[ "$CMDLINE" == *"nokaslr"* ]] && fail "Kernel cmdline: nokaslr present" || ok "Kernel cmdline: KASLR not disabled"
[[ "$CMDLINE" == *"module.sig_enforce=1"* ]] && ok "Kernel cmdline: module signature enforcement requested" || warn "Kernel cmdline: module.sig_enforce=1 not set"
[[ "$CMDLINE" == *"lockdown=confidentiality"* ]] && ok "Kernel cmdline: lockdown confidentiality requested" || warn "Kernel cmdline: lockdown=confidentiality not set"

if pacman -Qs microcode >/dev/null 2>&1; then ok "CPU microcode package installed"; else fail "CPU microcode package not detected"; fi

section "Firewall & Network"
NFT_RULESET=""
if has_cmd nft; then
    NFT_RULESET="$($SUDO nft list ruleset 2>/dev/null || true)"
fi
NFT_CONFIG=""
if [[ -r /etc/nftables.conf ]]; then
    NFT_CONFIG="$(< /etc/nftables.conf)"
fi
NFT_SOURCE="$NFT_RULESET"
NFT_SOURCE_LABEL="active ruleset"
NFT_INPUT_DROP=0
if [[ -z "$NFT_SOURCE" && -n "$NFT_CONFIG" ]]; then
    NFT_SOURCE="$NFT_CONFIG"
    NFT_SOURCE_LABEL="/etc/nftables.conf"
fi

if is_enabled nftables.service; then
    ok "nftables.service enabled at boot"
elif is_active nftables.service; then
    ok "nftables.service recently loaded rules"
else
    crit "nftables.service disabled; rules may not load at boot"
fi
if [[ -n "$NFT_SOURCE" ]]; then
    if nft_chain_has_policy_drop input "$NFT_SOURCE"; then
        NFT_INPUT_DROP=1
        ok "nftables: input policy DROP detected in $NFT_SOURCE_LABEL"
    else
        crit "nftables: input policy DROP not detected in $NFT_SOURCE_LABEL"
    fi
    nft_chain_has_policy_drop forward "$NFT_SOURCE" && ok "nftables: forward policy DROP detected in $NFT_SOURCE_LABEL" || fail "nftables: forward policy DROP not detected in $NFT_SOURCE_LABEL"
    nft_source_has 'ct state.*(established|related)' "$NFT_SOURCE" && ok "nftables: established/related rule detected in $NFT_SOURCE_LABEL" || fail "nftables: established/related rule missing in $NFT_SOURCE_LABEL"
    nft_source_has '(iifname "lo"|iif lo)' "$NFT_SOURCE" && ok "nftables: loopback allow rule detected in $NFT_SOURCE_LABEL" || fail "nftables: loopback allow rule missing in $NFT_SOURCE_LABEL"
    nft_source_has '(tcp dport 22|dport 22)' "$NFT_SOURCE" && ok "nftables: SSH port 22 rule detected in $NFT_SOURCE_LABEL" || warn "nftables: SSH port 22 rule not detected in $NFT_SOURCE_LABEL"
    nft_source_has '(limit rate|meter|hashlimit)' "$NFT_SOURCE" && ok "nftables: rate limiting primitive detected in $NFT_SOURCE_LABEL" || warn "nftables: no obvious rate limiting rule detected in $NFT_SOURCE_LABEL"
else
    warn "nftables: unable to read active ruleset or /etc/nftables.conf"
fi

check_sysctl_eq net.ipv4.ip_forward 0 fail "Network"
check_sysctl_eq net.ipv4.conf.all.accept_redirects 0 fail "Network"
check_sysctl_eq net.ipv4.conf.default.accept_redirects 0 fail "Network"
check_sysctl_eq net.ipv4.conf.all.accept_source_route 0 fail "Network"
check_sysctl_eq net.ipv4.conf.default.accept_source_route 0 fail "Network"
check_sysctl_eq net.ipv4.tcp_syncookies 1 fail "Network"
check_sysctl_eq net.ipv6.conf.all.accept_redirects 0 fail "Network IPv6"
check_sysctl_eq net.ipv6.conf.all.accept_source_route 0 fail "Network IPv6"

ACTIVE_IFACE="$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')"
if [[ -n "$ACTIVE_IFACE" ]]; then
    info "Default interface: $ACTIVE_IFACE"
    if [[ -r "/sys/class/net/$ACTIVE_IFACE/address" ]]; then
        CURRENT_MAC="$(<"/sys/class/net/$ACTIVE_IFACE/address")"
        PERM_MAC=""
        if has_cmd ethtool; then PERM_MAC="$(ethtool -P "$ACTIVE_IFACE" 2>/dev/null | awk '{print $3}')"; fi
        if [[ -z "$PERM_MAC" ]]; then PERM_MAC="$(ip link show "$ACTIVE_IFACE" 2>/dev/null | awk 'match($0, /permaddr ([0-9a-f:]{17})/, a) {print a[1]}')"; fi
        if [[ -n "$PERM_MAC" && "$CURRENT_MAC" != "$PERM_MAC" ]]; then ok "MAC privacy: current MAC differs from permanent MAC"; elif [[ -n "$PERM_MAC" ]]; then warn "MAC privacy: current MAC matches permanent MAC"; else warn "MAC privacy: permanent MAC unavailable"; fi
    fi
else
    warn "No default network interface detected"
fi

if ip link 2>/dev/null | awk '/PROMISC/ {found=1} END {exit !found}'; then fail "Network: interface in promiscuous mode detected"; else ok "Network: no PROMISC interface detected"; fi
if ip link show proton0 >/dev/null 2>&1; then ok "VPN: proton0 interface present"; else warn "VPN: proton0 interface not present"; fi

ALL_WILDCARD_LISTENERS="$($SUDO ss -H -tulpen 2>/dev/null | awk '($5 ~ /0\.0\.0\.0:/ || $5 ~ /\[::\]:/) {print}')"
LOCALSEND_LISTENERS="$(printf '%s\n' "$ALL_WILDCARD_LISTENERS" | awk 'tolower($0) ~ /localsend/ && $5 ~ /:53317$/ {print}')"
LISTENERS="$(printf '%s\n' "$ALL_WILDCARD_LISTENERS" | awk '!(tolower($0) ~ /localsend/ && $5 ~ /:53317$/)')"
if [[ -n "$LOCALSEND_LISTENERS" ]]; then
    ok "Exposure: LocalSend listener detected on TCP/UDP 53317"
fi
if [[ -z "$LISTENERS" ]]; then
    ok "Exposure: no wildcard public listeners detected"
elif [[ "$NFT_INPUT_DROP" -eq 1 ]]; then
    warn "Exposure: wildcard listeners detected, but nftables input DROP is present"
    printf '%s\n' "$LISTENERS" | awk '{print "  - " $1 " " $5 " " $NF}'
else
    fail "Exposure: wildcard listeners detected"
    printf '%s\n' "$LISTENERS" | awk '{print "  - " $1 " " $5 " " $NF}'
fi

if $SUDO ss -H -tulpen 2>/dev/null | awk '$5 ~ /:(5355|3702)$/ {found=1} END {exit !found}'; then
    fail "Privacy: LLMNR/WSDD listener detected on 5355/3702"
else
    ok "Privacy: no LLMNR/WSDD listener detected"
fi

section "SSH Hardening"
SSHD_HOSTKEY_FALLBACK=0
if has_cmd sshd; then
    SSHD_PROBE_ERROR="$(sshd -T 2>&1 >/dev/null || true)"
    [[ "$SSHD_PROBE_ERROR" == *"no hostkeys available"* ]] && SSHD_HOSTKEY_FALLBACK=1
fi
if is_active sshd.service || is_active ssh.service; then warn "SSH service is active; expected disabled unless needed"; else ok "SSH service inactive by default"; fi
SSHD_CONFIG="$(sshd_effective)"
if [[ -n "$SSHD_CONFIG" ]]; then
    check_sshd_key "$SSHD_CONFIG" port 22 warn
    check_sshd_key "$SSHD_CONFIG" permitrootlogin no critical
    check_sshd_key "$SSHD_CONFIG" passwordauthentication no fail
    check_sshd_key "$SSHD_CONFIG" pubkeyauthentication yes fail
    check_sshd_key "$SSHD_CONFIG" permitemptypasswords no critical
    check_sshd_key "$SSHD_CONFIG" x11forwarding no fail
    check_sshd_key "$SSHD_CONFIG" hostbasedauthentication no fail
    check_sshd_key "$SSHD_CONFIG" ignorerhosts yes fail
    check_sshd_key "$SSHD_CONFIG" permituserenvironment no fail
else
    if is_active sshd.service || is_active ssh.service; then
        warn "SSH: sshd effective config unavailable while SSH service is active"
    else
        info "SSH: effective config unavailable; SSH service is inactive"
    fi
fi

section "Kernel Hardening"
check_sysctl_eq kernel.randomize_va_space 2 critical "Memory"
check_sysctl_eq kernel.kptr_restrict 2 fail "Kernel"
check_sysctl_eq kernel.dmesg_restrict 1 fail "Kernel"
check_sysctl_eq kernel.unprivileged_bpf_disabled 1 fail "Kernel"
check_sysctl_eq net.core.bpf_jit_harden 2 fail "Kernel"
check_sysctl_eq fs.suid_dumpable 0 fail "Filesystem"
YAMA_PTRACE="$(sysctl_get kernel.yama.ptrace_scope)"
if [[ "$YAMA_PTRACE" == "1" || "$YAMA_PTRACE" == "2" || "$YAMA_PTRACE" == "3" ]]; then ok "Kernel: yama ptrace_scope=$YAMA_PTRACE"; else warn "Kernel: yama ptrace_scope=${YAMA_PTRACE:-unavailable}"; fi
if grep -qw nx /proc/cpuinfo 2>/dev/null; then ok "CPU: NX/XD bit present"; else crit "CPU: NX/XD bit not detected"; fi
if grep -qw smep /proc/cpuinfo 2>/dev/null; then ok "CPU: SMEP present"; else warn "CPU: SMEP not detected"; fi
if grep -qw smap /proc/cpuinfo 2>/dev/null; then ok "CPU: SMAP present"; else warn "CPU: SMAP not detected"; fi

section "MAC & Process Isolation"
if grep -qw apparmor /sys/kernel/security/lsm 2>/dev/null; then ok "LSM: AppArmor present in chain"; else fail "LSM: AppArmor not present in chain"; fi
if has_cmd aa-status; then
    AA_OUT="$($SUDO aa-status 2>/dev/null || true)"
    if printf '%s\n' "$AA_OUT" | grep -qi 'apparmor module is loaded'; then ok "AppArmor: module loaded"; else fail "AppArmor: module not loaded"; fi
    AA_ENFORCE="$(printf '%s\n' "$AA_OUT" | awk '/profiles are in enforce mode/ {print $1; exit}')"
    AA_COMPLAIN="$(printf '%s\n' "$AA_OUT" | awk '/profiles are in complain mode/ {print $1; exit}')"
    info "AppArmor profiles: enforce=${AA_ENFORCE:-0}, complain=${AA_COMPLAIN:-0}"
else
    warn "AppArmor: aa-status not installed"
fi
CGROUP_FS="$(stat -fc %T /sys/fs/cgroup 2>/dev/null || true)"
[[ "$CGROUP_FS" == "cgroup2fs" ]] && ok "Cgroups: unified v2 active" || warn "Cgroups: not unified v2 ($CGROUP_FS)"
if [[ -r /boot/config-"$(uname -r)" ]]; then
    if grep -Eq '^CONFIG_SECCOMP=y|^CONFIG_SECCOMP_FILTER=y' "/boot/config-$(uname -r)"; then
        ok "Seccomp: kernel support enabled"
    else
        fail "Seccomp: kernel support not detected in /boot/config-$(uname -r)"
    fi
elif [[ -r /proc/config.gz ]] && has_cmd zgrep; then
    if zgrep -Eq '^CONFIG_SECCOMP=y|^CONFIG_SECCOMP_FILTER=y' /proc/config.gz; then
        ok "Seccomp: kernel support enabled"
    else
        fail "Seccomp: kernel support not detected in /proc/config.gz"
    fi
else
    info "Seccomp: kernel config unavailable; current shell seccomp=$(awk '/^Seccomp:/ {print $2}' /proc/self/status 2>/dev/null)"
fi

section "Account Integrity"
UID0_USERS="$(awk -F: '$3 == 0 {print $1}' /etc/passwd 2>/dev/null | tr '\n' ' ')"
[[ "$UID0_USERS" == "root " || "$UID0_USERS" == "root" ]] && ok "Accounts: only root has UID 0" || crit "Accounts: unexpected UID 0 users: ${UID0_USERS:-none}"
if [[ "$HAVE_SUDO" -eq 1 ]]; then
    EMPTY_PASS="$($SUDO awk -F: '($2 == "") {print $1}' /etc/shadow 2>/dev/null | tr '\n' ' ')"
    [[ -z "$EMPTY_PASS" ]] && ok "Accounts: no empty-password accounts detected" || crit "Accounts: empty/disabled shadow marker review needed: $EMPTY_PASS"
else
    warn "Accounts: empty password check skipped without sudo"
fi
if grep -Rqs 'pam_faillock\.so' /etc/pam.d; then ok "PAM: pam_faillock present"; else info "PAM: pam_faillock not detected; password policy checks disabled by preference"; fi

section "Password Policy (Secondary)"
PASS_MAX="$(awk '$1 == "PASS_MAX_DAYS" {print $2}' /etc/login.defs 2>/dev/null | tail -n1)"
PASS_MIN="$(awk '$1 == "PASS_MIN_DAYS" {print $2}' /etc/login.defs 2>/dev/null | tail -n1)"
PASS_WARN="$(awk '$1 == "PASS_WARN_AGE" {print $2}' /etc/login.defs 2>/dev/null | tail -n1)"
[[ "$PASS_MAX" =~ ^[0-9]+$ && "$PASS_MAX" -le 90 ]] && ok "Password aging: PASS_MAX_DAYS=$PASS_MAX" || low "Password aging: PASS_MAX_DAYS=${PASS_MAX:-unset}, preferred <=90"
[[ "$PASS_MIN" =~ ^[0-9]+$ && "$PASS_MIN" -ge 1 ]] && ok "Password aging: PASS_MIN_DAYS=$PASS_MIN" || low "Password aging: PASS_MIN_DAYS=${PASS_MIN:-unset}, preferred >=1"
[[ "$PASS_WARN" =~ ^[0-9]+$ && "$PASS_WARN" -ge 7 ]] && ok "Password aging: PASS_WARN_AGE=$PASS_WARN" || low "Password aging: PASS_WARN_AGE=${PASS_WARN:-unset}, preferred >=7"

if [[ -r /etc/security/faillock.conf ]]; then
    DENY="$(awk -F= '/^[[:space:]]*deny[[:space:]]*=/{gsub(/[[:space:]]/, "", $2); print $2}' /etc/security/faillock.conf | tail -n1)"
    FAIL_INTERVAL="$(awk -F= '/^[[:space:]]*fail_interval[[:space:]]*=/{gsub(/[[:space:]]/, "", $2); print $2}' /etc/security/faillock.conf | tail -n1)"
    UNLOCK_TIME="$(awk -F= '/^[[:space:]]*unlock_time[[:space:]]*=/{gsub(/[[:space:]]/, "", $2); print $2}' /etc/security/faillock.conf | tail -n1)"
    [[ "$DENY" =~ ^[0-9]+$ && "$DENY" -le 5 ]] && ok "faillock: deny=$DENY" || low "faillock: deny=${DENY:-default/unset}, preferred explicit <=5"
    [[ "$FAIL_INTERVAL" =~ ^[0-9]+$ && "$FAIL_INTERVAL" -ge 900 ]] && ok "faillock: fail_interval=$FAIL_INTERVAL" || low "faillock: fail_interval=${FAIL_INTERVAL:-default/unset}, preferred >=900"
    [[ "$UNLOCK_TIME" =~ ^[0-9]+$ && "$UNLOCK_TIME" -ge 900 ]] && ok "faillock: unlock_time=$UNLOCK_TIME" || low "faillock: unlock_time=${UNLOCK_TIME:-default/unset}, preferred >=900"
else
    low "faillock: /etc/security/faillock.conf missing"
fi

if [[ -r /etc/security/pwquality.conf ]]; then
    MINLEN="$(awk -F= '/^[[:space:]]*minlen[[:space:]]*=/{gsub(/[[:space:]]/, "", $2); print $2}' /etc/security/pwquality.conf | tail -n1)"
    [[ "$MINLEN" =~ ^[0-9]+$ && "$MINLEN" -ge 14 ]] && ok "pwquality: minlen=$MINLEN" || low "pwquality: minlen=${MINLEN:-unset}, preferred >=14"
    for key in lcredit ucredit dcredit ocredit; do
        value="$(awk -F= -v k="$key" '$1 ~ "^[[:space:]]*" k "[[:space:]]*$" {gsub(/[[:space:]]/, "", $2); print $2}' /etc/security/pwquality.conf | tail -n1)"
        [[ "$value" == "-1" ]] && ok "pwquality: $key=$value" || low "pwquality: $key=${value:-unset}, preferred -1"
    done
else
    low "pwquality: /etc/security/pwquality.conf missing"
fi
info "Password policy is reported as secondary on this machine; remediation script does not change it"

section "Logging & Audit"
if is_active auditd.service; then ok "auditd.service active"; else warn "auditd.service inactive; optional on this lab/privacy profile"; fi
if has_cmd auditctl; then
    AUDIT_RULES="$($SUDO auditctl -l 2>/dev/null || true)"
    [[ -n "$AUDIT_RULES" ]] && ok "auditd: runtime rules loaded" || warn "auditd: no runtime rules visible"
    for key in time-change identity logins privileged delete modules; do
        printf '%s\n' "$AUDIT_RULES" | grep -q -- "$key" && ok "auditd: rule key '$key' present" || warn "auditd: rule key '$key' missing"
    done
    printf '%s\n' "$AUDIT_RULES" | grep -q -- perm_mod && ok "auditd: rule key 'perm_mod' present" || low "auditd: rule key 'perm_mod' missing; optional in lab/privacy profile"
else
    warn "auditd: auditctl not installed"
fi

if [[ -d /var/log/journal ]]; then ok "journald: persistent journal directory exists"; else warn "journald: /var/log/journal missing; storage may be volatile"; fi
JCONF="$(systemd-analyze cat-config systemd/journald.conf 2>/dev/null || true)"
printf '%s\n' "$JCONF" | grep -Eq '^[^#]*Storage=persistent' && ok "journald: Storage=persistent" || warn "journald: Storage=persistent not detected"
printf '%s\n' "$JCONF" | grep -Eq '^[^#]*SystemMaxUse=' && ok "journald: SystemMaxUse configured" || warn "journald: SystemMaxUse not configured"
printf '%s\n' "$JCONF" | grep -Eq '^[^#]*MaxRetentionSec=' && ok "journald: MaxRetentionSec configured" || warn "journald: MaxRetentionSec not configured"

section "Filesystem & Permissions"
check_file_perm_any /etc/passwd 'root:root' '644' critical
check_file_perm_any /etc/shadow 'root:root root:shadow' '640 600 400 000' critical
check_file_perm_any /etc/group 'root:root' '644' fail
check_file_perm_any /etc/gshadow 'root:root root:shadow' '640 600 400 000' fail
check_file_perm_any /etc/sudoers 'root:root' '440' critical
[[ -e /etc/ssh/sshd_config ]] && check_file_perm_any /etc/ssh/sshd_config 'root:root' '600 640 644' warn
[[ -e /etc/nftables.conf ]] && check_file_perm_any /etc/nftables.conf 'root:root' '600 640 644' fail
[[ -d /home/archer ]] && check_file_perm_any /home/archer 'archer:archer' '700 750' fail

if mount | awk '$3 == "/dev/shm" && $0 ~ /nodev/ && $0 ~ /nosuid/ {found=1} END {exit !found}'; then
    ok "Mounts: /dev/shm has nodev,nosuid"
    if mount | awk '$3 == "/dev/shm" && $0 ~ /noexec/ {found=1} END {exit !found}'; then
        ok "Mounts: /dev/shm has noexec"
    else
        warn "Mounts: /dev/shm lacks noexec; accepted for lab/tooling compatibility"
    fi
else
    fail "Mounts: /dev/shm missing nodev,nosuid"
fi

WW_NOSTICKY="$($SUDO find / -xdev -type d -perm -0002 ! -perm -1000 -print -quit 2>/dev/null || true)"
if [[ -z "$WW_NOSTICKY" ]]; then
    ok "Filesystem: no world-writable directory without sticky bit on root fs"
elif [[ "$WW_NOSTICKY" == /home/archer/DaVinci\ Resolve\ Media* || "$WW_NOSTICKY" == /home/archer/.local/share/DaVinciResolve* || "$WW_NOSTICKY" == /opt/resolve/.license* ]]; then
    warn "Filesystem: accepted DaVinci world-writable exception; prefer sticky bit where compatible"
else
    crit "Filesystem: world-writable directory without sticky bit: $WW_NOSTICKY"
fi

section "Service Minimization & Privacy Agents"
FAILED_SERVICES="$(systemctl --failed --no-legend 2>/dev/null | wc -l)"
[[ "$FAILED_SERVICES" -eq 0 ]] && ok "systemd: no failed services" || fail "systemd: $FAILED_SERVICES failed service(s)"

for svc in telnet.socket telnet.service rsh.service rlogin.service tftp.service avahi-daemon.service cups.service rpcbind.service smb.service snmpd.service; do
    if is_active "$svc"; then fail "Dangerous/noisy service active: $svc"; fi
done

is_active usbguard.service && ok "USBGuard active" || warn "USBGuard inactive"
if is_active opensnitchd.service || is_active opensnitch.service; then ok "OpenSnitch daemon active"; else warn "OpenSnitch daemon inactive"; fi

if is_active tor.service; then
    ok "Tor service active"
    if has_cmd systemd-analyze; then
        TOR_SCORE_RAW="$(systemd-analyze security tor.service 2>/dev/null | awk '/Overall exposure level/ {for (i=1; i<=NF; i++) if ($i ~ /^[0-9]+(\.[0-9]+)?$/) {print $i; exit}}')"
        if [[ "$TOR_SCORE_RAW" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            TOR_INT="${TOR_SCORE_RAW%%.*}"
            [[ "$TOR_INT" -lt 6 ]] && ok "Tor systemd exposure score: $TOR_SCORE_RAW" || warn "Tor systemd exposure score high: $TOR_SCORE_RAW"
        else
            warn "Tor systemd exposure score unavailable"
        fi
    fi
    if ss -H -ltn 2>/dev/null | awk '$4 ~ /^127\.0\.0\.1:9050$/ {found=1} END {exit !found}'; then ok "Tor SOCKS listener bound to 127.0.0.1:9050"; else warn "Tor SOCKS listener not detected on 127.0.0.1:9050"; fi
else
    info "Tor service inactive"
fi

section "DNS & Online Privacy"
if is_active systemd-resolved.service; then ok "systemd-resolved active"; else warn "systemd-resolved inactive"; fi
if [[ -L /etc/resolv.conf ]]; then
    RESOLV_TARGET="$(readlink /etc/resolv.conf 2>/dev/null || true)"
    info "/etc/resolv.conf -> $RESOLV_TARGET"
    [[ "$RESOLV_TARGET" == *stub-resolv.conf* || "$RESOLV_TARGET" == *systemd* ]] && ok "Resolver uses systemd-resolved stub" || warn "Resolver symlink target is unusual"
else
    warn "/etc/resolv.conf is not a symlink"
fi
if has_cmd resolvectl; then
    DNS_STATUS="$(resolvectl status 2>/dev/null || true)"
    printf '%s\n' "$DNS_STATUS" | grep -Eqi 'mullvad|quad9|cloudflare|dns\.mullvad\.net' && ok "DNS: privacy-oriented resolver detected" || warn "DNS: Mullvad/Quad9/Cloudflare not detected in resolvectl"
    printf '%s\n' "$DNS_STATUS" | grep -Eqi 'DNSOverTLS=yes|DNSOverTLS: yes|DNSSEC=yes|DNSSEC: yes' && ok "DNS: encrypted/validated DNS indication detected" || warn "DNS: DNS-over-TLS/DNSSEC not clearly enabled"
fi

if [[ "$ONLINE" -eq 1 ]]; then
    if has_cmd curl; then
        PUBLIC_IP="$(curl --fail --silent --show-error --connect-timeout 5 https://api.ipify.org 2>/dev/null || true)"
        [[ -n "$PUBLIC_IP" ]] && info "Public IP: $PUBLIC_IP" || warn "Online: public IP lookup failed"
        if is_active tor.service; then
            TOR_TEST="$(curl --socks5-hostname 127.0.0.1:9050 --fail --silent --connect-timeout 10 https://check.torproject.org/api/ip 2>/dev/null || true)"
            [[ "$TOR_TEST" == *'"IsTor":true'* || "$TOR_TEST" == *'"IsTor": true'* ]] && ok "Tor exit test: functional" || fail "Tor exit test: failed or not using Tor"
        fi
    else
        warn "Online checks requested but curl is not installed"
    fi
else
    info "Online checks skipped; run with --online to test public IP/Tor exit"
fi

section "Containers & Package Integrity"
if has_cmd podman; then
    ok "Podman installed"
    PODMAN_INFO="$(podman info 2>/dev/null || true)"
    printf '%s\n' "$PODMAN_INFO" | grep -qi 'rootless: true' && ok "Podman rootless mode detected" || warn "Podman rootless mode not confirmed"
    PODMAN_PRIV="$($SUDO podman ps -q 2>/dev/null | xargs -r podman inspect --format '{{.Name}} {{.HostConfig.Privileged}}' 2>/dev/null | awk '$2 == "true" {print}')"
    [[ -z "$PODMAN_PRIV" ]] && ok "Podman: no privileged running containers detected" || crit "Podman: privileged containers detected: $PODMAN_PRIV"
else
    info "Podman not installed"
fi
if [[ -S /var/run/docker.sock || -S /run/docker.sock ]]; then
    warn "Docker socket present; membership grants root-equivalent control"
else
    ok "Docker socket not present"
fi

if [[ -r /etc/pacman.conf ]]; then
    grep -Eq '^[[:space:]]*SigLevel[[:space:]]*=[[:space:]]*.*Required' /etc/pacman.conf && ok "Pacman: package signatures required" || fail "Pacman: SigLevel Required not detected"
else
    warn "Pacman: /etc/pacman.conf missing"
fi
check_pkg_installed arch-audit "Arch security advisory checker"
check_pkg_installed aide "AIDE file integrity monitor"

if has_cmd getcap; then
    CAP_COUNT="$($SUDO getcap -r /usr/bin /usr/sbin 2>/dev/null | wc -l)"
    info "File capabilities under /usr/bin,/usr/sbin: $CAP_COUNT"
else
    warn "getcap unavailable; file capability audit skipped"
fi

section "Summary"
TOTAL=$((OK_COUNT + INFO_COUNT + LOW_COUNT + WARN_COUNT + FAIL_COUNT + CRIT_COUNT))
RISK_DENOM=$((OK_COUNT + (LOW_COUNT / 2) + WARN_COUNT + (FAIL_COUNT * 2) + (CRIT_COUNT * 4)))
if [[ "$RISK_DENOM" -gt 0 ]]; then
    SCORE=$((OK_COUNT * 100 / RISK_DENOM))
else
    SCORE=100
fi
printf 'Checks: %d | OK: %b%d%b | INFO: %d | LOW: %b%d%b | WARN: %b%d%b | FAIL: %b%d%b | CRITICAL: %b%d%b\n' \
    "$TOTAL" "$GREEN" "$OK_COUNT" "$NC" "$INFO_COUNT" "$CYAN" "$LOW_COUNT" "$NC" "$YELLOW" "$WARN_COUNT" "$NC" "$RED" "$FAIL_COUNT" "$NC" "$RED" "$CRIT_COUNT" "$NC"
printf 'Approximate posture score: %b%d/100%b\n' "$CYAN" "$SCORE" "$NC"

if [[ "${#FINDINGS[@]}" -gt 0 ]]; then
    printf '\n%bPrioritized findings:%b\n' "$WHITE" "$NC"
    for finding in "${FINDINGS[@]}"; do
        printf '  - %s\n' "$finding"
    done
else
    printf '\n%bNo WARN/FAIL/CRITICAL findings recorded.%b\n' "$GREEN" "$NC"
fi

printf '\n%bAUDIT COMPLETE.%b\n' "$CYAN" "$NC"
