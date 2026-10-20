
# Global security profile for OpenCode AI Agent

# Inherit base system protections (includes /proc and /sys isolation)
include default.profile

# Filesystem Protection
blacklist ${HOME}/Secrets
whitelist ${HOME}/.config/opencode

# System and Binary Protection (Read-Only)
# Ensures it cannot modify any global command, library, or configuration.
read-only /bin
read-only /sbin
read-only /usr
read-only /etc

# Hardware, disk, and process isolation
# disable-mnt is critical: prevents access to other mounted partitions 
# (for example: dual boot partitions in /mnt or /run/media).
disable-mnt
ipc-namespace
machine-id
nodvd
nosound
nou2f
