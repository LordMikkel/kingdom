#!/usr/bin/env bash
# Restore network connectivity.
#
# Usage: sudo net-restore.sh [--stop <user-unit>]

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

STOP_UNIT=""
if [[ "$1" == "--stop" && -n "$2" ]]; then
    STOP_UNIT="$2"
fi

# 1. Root required
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[!] Run it with sudo: sudo $0 $*${NC}"
    exit 1
fi

TARGET_USER="${SUDO_USER:-$USER}"

# 2. Optionally stop a user unit of $TARGET_USER
if [[ -n "$STOP_UNIT" ]]; then
    if systemctl --user -M "${TARGET_USER}@" stop "$STOP_UNIT" 2>/dev/null; then
        echo -e "${YELLOW}[+] $STOP_UNIT stopped.${NC}"
    else
        echo -e "${YELLOW}[-] Could not stop $STOP_UNIT.${NC}"
    fi
fi

# 3. Unblock radios
rfkill unblock all
echo -e "${GREEN}[+] rfkill: all radios unblocked.${NC}"

# 4. Make sure NetworkManager is running
if ! systemctl is-active --quiet NetworkManager; then
    systemctl start NetworkManager
    echo -e "${GREEN}[+] NetworkManager started.${NC}"
fi

# 5. Enable networking (the disabled state persists across reboots)
nmcli networking on
nmcli radio wifi on
echo -e "${GREEN}[+] Networking and Wi-Fi enabled in NetworkManager.${NC}"

# 6. Wait for connectivity; restart NM once if it doesn't come back
wait_online() {
    for _ in $(seq 1 15); do
        [[ "$(nmcli -t -f CONNECTIVITY general)" == "full" ]] && return 0
        sleep 1
    done
    return 1
}

if ! wait_online; then
    echo -e "${YELLOW}[*] No connectivity yet, restarting NetworkManager...${NC}"
    systemctl restart NetworkManager
    sleep 2
    nmcli networking on
    wait_online
fi

# 7. Report
echo
nmcli general
echo
if [[ "$(nmcli -t -f CONNECTIVITY general)" == "full" ]]; then
    echo -e "${GREEN}[✓] Internet restored.${NC}"
else
    echo -e "${RED}[!] Still no full connectivity. Check: nmcli device status${NC}"
    exit 1
fi
