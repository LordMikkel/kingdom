#!/usr/bin/env bash

RANDOMIZER_CONF="/etc/NetworkManager/conf.d/mac-randomize.conf"
BAK_FILE="${RANDOMIZER_CONF}.bak"

# Colors for terminal output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}[*] Starting ProtonVPN Kill Switch cleanup...${NC}"

# 1. Check for root privileges
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[!] This script must be run with sudo.${NC}" 
   exit 1
fi

# 2. Disable and backup the randomizer
if [[ -f "$RANDOMIZER_CONF" ]]; then
    mv "$RANDOMIZER_CONF" "$BAK_FILE"
    echo -e "${GREEN}[+] Randomizer temporarily moved to .bak.${NC}"
else
    echo "[-] Active randomizer file not found, skipping step."
fi

# 3. Delete the ProtonVPN dummy interface
if ip link show pvpnksintrf0 &> /dev/null; then
    ip link delete pvpnksintrf0
    echo -e "${GREEN}[+] Virtual interface pvpnksintrf0 deleted.${NC}"
fi

# 4. Delete the kill switch connection profile
if nmcli connection show pvpn-killswitch &> /dev/null; then
    nmcli connection delete pvpn-killswitch
    echo -e "${GREEN}[+] Connection pvpn-killswitch removed from NetworkManager.${NC}"
fi

# 5. Return physical interfaces to managed state
for dev in /sys/class/net/*; do
    [ -e "$dev/device" ] && nmcli device set "${dev##*/}" managed yes
done
echo -e "${GREEN}[+] Network interfaces returned to 'managed' state.${NC}"

# 6. Reload systemd manager configuration (clears any unit warnings)
echo -e "${GREEN}[*] Reloading systemd services...${NC}"
systemctl daemon-reload

# 7. First NetworkManager restart (clean state)
systemctl restart NetworkManager
echo -e "${GREEN}[+] NetworkManager restarted in a clean state.${NC}"

# Give NM a few seconds to bring up and stabilize the interfaces
sleep 3

# 8. Restore the randomizer
if [[ -f "$BAK_FILE" ]]; then
    mv "$BAK_FILE" "$RANDOMIZER_CONF"
fi
