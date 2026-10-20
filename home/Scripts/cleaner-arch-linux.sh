#!/usr/bin/env bash
# ==============================================================================
#  ULTIMATE LINUX CLEANER
#  Combines detailed reporting with Arch Linux specific power tools.
#
#  Usage: cleaner-arch-linux.sh [-n|--dry-run] [-y|--yes] [-h|--help]
#    -n, --dry-run   Show what would be cleaned without deleting anything
#    -y, --yes       Answer "yes" to every prompt (non-interactive)
# ==============================================================================

set -uo pipefail
shopt -s nullglob

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

DRY_RUN=0
ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        -n|--dry-run) DRY_RUN=1 ;;
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help) sed -n '6,8p' "$0" | sed 's/^#  \?//'; exit 0 ;;
        *) echo -e "${RED}Unknown option: $arg${NC}"; exit 1 ;;
    esac
done

# Check if running as root
if [ "$EUID" -eq 0 ]; then
   echo -e "${RED}Please do not run this script as root.${NC}"
   echo "Run as your normal user. Sudo password will be requested for system tasks."
   exit 1
fi

echo -e "${BLUE}${BOLD}=== Ultimate Arch System Cleaner ===${NC}"
[ "$DRY_RUN" -eq 1 ] && echo -e "${YELLOW}${BOLD}DRY RUN: nothing will be deleted.${NC}"
echo "Starting cleanup process..."
echo ""

# --- 0. HELPERS ---
cleaned_count=0
total_freed_bytes=0
last_freed=0

human() {
    numfmt --to=iec-i --suffix=B "$1" 2>/dev/null || echo "${1}B"
}

# ask "Question" -> 0 if yes. Honors --yes.
ask() {
    if [ "$ASSUME_YES" -eq 1 ]; then
        echo "$1 (y/N): y"
        return 0
    fi
    read -p "$1 (y/N): " -n 1 -r
    echo ""
    [[ $REPLY =~ ^[Yy]$ ]]
}

# run cmd... -> executes, or just prints it in dry-run mode
run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo -e "  [dry-run] $*"
    else
        "$@"
    fi
}

avail_bytes() {
    df -B1 --output=avail "$1" 2>/dev/null | tail -1 | tr -d ' '
}

clean_directory() {
    local dir="$1"
    local description="$2"
    local silent="${3:-}"
    last_freed=0

    [ -d "$dir" ] || return 0
    local size
    size=$(du -sb "$dir" 2>/dev/null | awk '{print $1}')
    # Empty directories still report their own inode (~4KB)
    [ -n "$size" ] && [ "$size" -gt 4096 ] || return 0

    [ "$silent" != "silent" ] && echo -e "${YELLOW}Cleaning: ${description}${NC}"
    if [ "$DRY_RUN" -eq 0 ]; then
        find "$dir" -mindepth 1 -delete 2>/dev/null
        local left
        left=$(du -sb "$dir" 2>/dev/null | awk '{print $1}')
        size=$((size - ${left:-0}))
    fi
    cleaned_count=$((cleaned_count + 1))
    last_freed=$size
    total_freed_bytes=$((total_freed_bytes + size))
    [ "$silent" != "silent" ] && echo -e "${GREEN}  ✓ Freed: $(human "$size")${NC}"
    return 0
}

# clean_old_files dir days description -> deletes files modified more than <days> ago
clean_old_files() {
    local dir="$1" days="$2" description="$3"
    [ -d "$dir" ] || return 0
    local size
    size=$(find "$dir" -type f -mtime +"$days" -printf '%s\n' 2>/dev/null \
        | awk '{s+=$1} END {print s+0}')
    [ "$size" -gt 0 ] || return 0
    echo -e "${YELLOW}Cleaning: ${description}${NC}"
    [ "$DRY_RUN" -eq 0 ] && find "$dir" -type f -mtime +"$days" -delete 2>/dev/null
    cleaned_count=$((cleaned_count + 1))
    total_freed_bytes=$((total_freed_bytes + size))
    echo -e "${GREEN}  ✓ Freed: $(human "$size")${NC}"
}

# Chromium/Electron cache subfolders (all safe to delete, rebuilt on demand)
CHROMIUM_CACHE_NAMES=("Cache" "Code Cache" "GPUCache" "DawnCache" "DawnGraphiteCache"
    "DawnWebGPUCache" "GrShaderCache" "GraphiteDawnCache" "ShaderCache"
    "Service Worker/CacheStorage" "Service Worker/ScriptCache")

# clean_chromium_tree root label -> cleans root and its Default/Profile N dirs
clean_chromium_tree() {
    local root="$1" label="$2" freed=0 d n
    [ -d "$root" ] || return 0
    for d in "$root" "$root/Default" "$root"/Profile\ *; do
        for n in "${CHROMIUM_CACHE_NAMES[@]}"; do
            clean_directory "$d/$n" "$label" "silent"
            freed=$((freed + last_freed))
        done
    done
    if [ "$freed" -gt 0 ]; then
        echo -e "${YELLOW}Cleaning: ${label}${NC}"
        echo -e "${GREEN}  ✓ Freed: $(human "$freed")${NC}"
    fi
}

# --- 1. PROCESS MANAGEMENT ---
running_programs=()
apps_to_check=("code" "zeditor" "zed-editor" "chromium" "brave" "vivaldi-bin" "zen"
    "obsidian" "signal-desktop" "resolve" "slack" "discord" "spotify" "ollama")

for app in "${apps_to_check[@]}"; do
    if pgrep -x "$app" > /dev/null; then
        running_programs+=("$app")
    fi
done

if [ ${#running_programs[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠ Warning: The following programs are currently running:${NC}"
    for program in "${running_programs[@]}"; do
        echo -e "  - $program"
    done
    echo ""
    echo -e "${YELLOW}Closing them is recommended for effective cleaning.${NC}"
    echo ""
    if ask "Do you want to attempt to close them automatically?"; then
        for program in "${running_programs[@]}"; do
            if [ "$DRY_RUN" -eq 1 ]; then
                echo "  [dry-run] pkill -x $program"
            elif pkill -x "$program"; then
                echo -e "${GREEN}  ✓ Closed $program${NC}"
            else
                echo -e "${RED}  ✗ Could not close $program${NC}"
            fi
        done
        [ "$DRY_RUN" -eq 0 ] && sleep 2
    else
        echo "Continuing without closing programs..."
    fi
    echo ""
fi

# Flatpak apps currently running are skipped when cleaning their data
running_flatpaks=""
if command -v flatpak &> /dev/null; then
    running_flatpaks=$(flatpak ps --columns=application 2>/dev/null)
fi
flatpak_running() {
    grep -qxF "$1" <<< "$running_flatpaks"
}

# --- 2. SETUP ---
root_avail_before=$(avail_bytes /)
home_mount=$(findmnt -no TARGET -T "$HOME" 2>/dev/null)
home_avail_before=$(avail_bytes "$HOME")

if [ "$DRY_RUN" -eq 0 ]; then
    # Ask for sudo once and keep the ticket alive until the script exits
    sudo -v || exit 1
    while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
fi

# --- 3. ARCH SYSTEM CLEANUP (Root actions) ---
echo -e "${BLUE}${BOLD}=== Arch System (Requires Sudo) ===${NC}"

echo -e "${YELLOW}Cleaning: Corrupted or partial pacman downloads${NC}"
# pacman 6+ leaves download-XXXXXX *directories* behind
run sudo rm -rf /var/cache/pacman/pkg/*.part /var/cache/pacman/pkg/download-*

# Pacman Cache
if command -v paccache &> /dev/null; then
    echo -e "${YELLOW}Cleaning: Pacman Cache (keeping last 2 versions)${NC}"
    run sudo paccache -rk2
    echo -e "${YELLOW}Cleaning: Uninstalled Packages Cache${NC}"
    run sudo paccache -ruk0
else
    echo -e "${YELLOW}Cleaning: Pacman Cache (Default -Sc)${NC}"
    run sudo pacman -Sc --noconfirm
fi

# AUR Helpers
if command -v paru &> /dev/null; then
    echo -e "${YELLOW}Cleaning: Paru (AUR) Cache${NC}"
    run paru -Sc --noconfirm
elif command -v yay &> /dev/null; then
    echo -e "${YELLOW}Cleaning: Yay (AUR) Cache${NC}"
    run yay -Sc --noconfirm
fi

# Flatpak
if command -v flatpak &> /dev/null; then
    echo -e "${YELLOW}Cleaning: Flatpak Unused Runtimes${NC}"
    run flatpak uninstall --unused -y
    clean_directory "$HOME/.cache/flatpak" "Flatpak User Cache" "silent"
fi

# Orphans (Safe Array Handling)
echo -e "${YELLOW}Checking: Orphaned packages${NC}"
mapfile -t orphans < <(pacman -Qtdq)
if [ ${#orphans[@]} -gt 0 ] && [ -n "${orphans[0]}" ]; then
    echo -e "${RED}Found orphans: ${orphans[*]}${NC}"
    if ask "Remove these orphans?"; then
        run sudo pacman -Rns "${orphans[@]}" --noconfirm
        echo -e "${GREEN}  ✓ Orphans removed${NC}"
    fi
else
    echo -e "  No orphans found."
fi

# Systemd Journal
echo -e "${YELLOW}Cleaning: System Logs (Journalctl)${NC}"
run sudo journalctl --vacuum-time=2weeks --vacuum-size=50M

# Core dumps (crashed programs, can silently take GBs)
if [ -d /var/lib/systemd/coredump ]; then
    echo -e "${YELLOW}Cleaning: Systemd core dumps${NC}"
    run sudo find /var/lib/systemd/coredump -type f -delete
fi

# /tmp and /var/tmp according to tmpfiles.d age rules
echo -e "${YELLOW}Cleaning: Old files in /tmp and /var/tmp (systemd-tmpfiles)${NC}"
run sudo systemd-tmpfiles --clean

# .pacnew files are not cleaned, just reported
if command -v pacdiff &> /dev/null; then
    pacnew_count=$(pacdiff -o 2>/dev/null | wc -l)
    if [ "$pacnew_count" -gt 0 ]; then
        echo -e "${YELLOW}  ℹ $pacnew_count .pacnew/.pacsave file(s) pending. Review with: sudo pacdiff${NC}"
    fi
fi
echo ""

# --- 4. USER APPLICATIONS CACHE ---
echo -e "${BLUE}${BOLD}=== User Applications ===${NC}"

# VSCode & JetBrains (Cache/Code Cache/GPUCache handled by the Electron loop below)
clean_directory "$HOME/.config/Code/CachedData" "VSCode Cached Data"
clean_directory "$HOME/.config/Code/CachedExtensionVSIXs" "VSCode Cached Extension VSIXs"
clean_directory "$HOME/.config/Code/logs" "VSCode Logs"
clean_directory "$HOME/.cache/JetBrains" "JetBrains IDEs Cache"

# Zed Editor
clean_directory "$HOME/.cache/zed" "Zed Cache"
clean_directory "$HOME/.local/share/zed/logs" "Zed Logs"

# Neovim LSP log grows forever
nvim_lsp_log="$HOME/.local/state/nvim/lsp.log"
if [ -f "$nvim_lsp_log" ] && [ "$(stat -c %s "$nvim_lsp_log")" -gt 10485760 ]; then
    echo -e "${YELLOW}Cleaning: Neovim LSP log${NC}"
    total_freed_bytes=$((total_freed_bytes + $(stat -c %s "$nvim_lsp_log")))
    run truncate -s 0 "$nvim_lsp_log"
fi

# AI Agents (OpenCode, Claude Code)
clean_directory "$HOME/.cache/opencode" "OpenCode Cache"
clean_directory "$HOME/.opencode/cache" "OpenCode Local Cache"
clean_directory "$HOME/.local/state/opencode" "OpenCode State/Logs"
clean_old_files "$HOME/.cache/claude-cli-nodejs" 7 "Claude Code MCP logs (>7 days)"

# Multimedia y Editing
clean_directory "$HOME/.cache/darktable" "Darktable Cache"
clean_directory "$HOME/.local/share/DaVinciResolve/logs" "DaVinci Resolve Logs"
clean_directory "$HOME/.cache/yt-dlp" "yt-dlp Cache"

# Browsers (Chromium based: every profile, not only Default)
for base in "$HOME/.config" "$HOME/.cache"; do
    clean_chromium_tree "$base/chromium" "Chromium Cache (${base#$HOME/})"
    clean_chromium_tree "$base/google-chrome" "Chrome Cache (${base#$HOME/})"
    clean_chromium_tree "$base/BraveSoftware/Brave-Browser" "Brave Cache (${base#$HOME/})"
    clean_chromium_tree "$base/vivaldi" "Vivaldi Cache (${base#$HOME/})"
done
if ! flatpak_running com.vivaldi.Vivaldi; then
    clean_chromium_tree "$HOME/.var/app/com.vivaldi.Vivaldi/config/vivaldi" "Vivaldi (Flatpak) Cache"
fi
# Firefox based (native; Zen and Mullvad Flatpaks are covered by the Flatpak loop)
clean_directory "$HOME/.cache/mozilla" "Firefox Cache"
clean_directory "$HOME/.cache/zen" "Zen Browser Cache"

# Electron apps (VSCode, Obsidian, Signal, Slack, Discord...), native and Flatpak
electron_freed=0
for app_dir in "$HOME/.config"/*/ "$HOME/.var/app"/*/config/*/; do
    app_dir="${app_dir%/}"
    case "$app_dir" in
        */chromium|*/google-chrome|*/BraveSoftware|*/vivaldi) continue ;;
    esac
    if [[ "$app_dir" == "$HOME/.var/app/"* ]]; then
        app_id="${app_dir#$HOME/.var/app/}"
        flatpak_running "${app_id%%/*}" && continue
    fi
    for n in "${CHROMIUM_CACHE_NAMES[@]}"; do
        clean_directory "$app_dir/$n" "Electron cache" "silent"
        electron_freed=$((electron_freed + last_freed))
    done
done
if [ "$electron_freed" -gt 0 ]; then
    echo -e "${YELLOW}Cleaning: Electron apps caches${NC}"
    echo -e "${GREEN}  ✓ Freed: $(human "$electron_freed")${NC}"
fi

# Flatpak apps caches (Zen, Mullvad, Vivaldi, Obsidian, VLC, Signal, LibreOffice...)
flatpak_freed=0
for cache_dir in "$HOME/.var/app"/*/cache; do
    app_id="${cache_dir#$HOME/.var/app/}"
    app_id="${app_id%/cache}"
    if flatpak_running "$app_id"; then
        echo -e "  Skipping $app_id (running)"
        continue
    fi
    clean_directory "$cache_dir" "Flatpak $app_id" "silent"
    flatpak_freed=$((flatpak_freed + last_freed))
done
clean_directory "$HOME/.var/app/com.usebottles.bottles/data/bottles/temp" "Bottles temp" "silent"
flatpak_freed=$((flatpak_freed + last_freed))
if [ "$flatpak_freed" -gt 0 ]; then
    echo -e "${YELLOW}Cleaning: Flatpak apps caches${NC}"
    echo -e "${GREEN}  ✓ Freed: $(human "$flatpak_freed")${NC}"
fi

if ! pgrep -x "chrome" > /dev/null; then
    singleton_items=("$HOME/.config/google-chrome"/Singleton*)
    if [ ${#singleton_items[@]} -gt 0 ]; then
        echo -e "${YELLOW}Cleaning: Chrome Singleton lock files${NC}"
        run rm -f "${singleton_items[@]}"
        echo -e "${GREEN}  ✓ Removed stale lock files${NC}"
    fi
fi

# Slack, Spotify & Steam/Proton
clean_directory "$HOME/.config/Slack/Cache" "Slack Cache"
clean_directory "$HOME/.cache/spotify" "Spotify Cache"
clean_directory "$HOME/.steam/steam/appcache" "Steam AppCache"
clean_directory "$HOME/.cache/winetricks" "Winetricks/Proton Downloads"

# Cyber / Security tools (never touches potfiles, loot or scan results)
clean_directory "$HOME/.msf4/logs" "Metasploit Logs"
clean_directory "$HOME/.cache/hashcat/kernels" "Hashcat compiled kernels"
clean_directory "$HOME/.hashcat/kernels" "Hashcat compiled kernels (legacy)"
zap_logs=("$HOME/.ZAP"/zap.log.*)
if [ ${#zap_logs[@]} -gt 0 ]; then
    echo -e "${YELLOW}Cleaning: OWASP ZAP rotated logs${NC}"
    run rm -f "${zap_logs[@]}"
fi

# --- 5. DAVINCI RESOLVE HEAVY CACHE ---
echo ""
echo -e "${BLUE}${BOLD}=== DaVinci Resolve Media Cache ===${NC}"
echo -e "${YELLOW}Note: Clearing this will force Resolve to re-render proxies and timelines on old projects.${NC}"
if ask "Do you want to clear the global CacheClip and .gallery folders?"; then
    RESOLVE_MEDIA_ROOT="$HOME/Videos"
    if [ -d "$RESOLVE_MEDIA_ROOT/CacheClip" ] || [ -d "$RESOLVE_MEDIA_ROOT/.gallery" ]; then
        clean_directory "$RESOLVE_MEDIA_ROOT/CacheClip" "DaVinci CacheClip (Render/Proxies)"
        clean_directory "$RESOLVE_MEDIA_ROOT/.gallery" "DaVinci Gallery (Stills)"
    else
        echo -e "${RED}  No CacheClip or .gallery found in $RESOLVE_MEDIA_ROOT${NC}"
    fi
else
    echo "Skipping DaVinci Resolve media cache."
fi

# Gnome / System Specifics
echo ""
echo -e "${BLUE}${BOLD}=== Gnome & Trash ===${NC}"
clean_directory "$HOME/.cache/thumbnails" "Thumbnails (Nautilus/Thunar)"
clean_directory "$HOME/.cache/tracker3" "Gnome Tracker Database"
if ask "Empty the trash (all drives)?"; then
    if command -v trash-empty &> /dev/null; then
        # trash-cli also empties the .Trash-UID folders on other mounted drives
        run trash-empty -f
    else
        clean_directory "$HOME/.local/share/Trash" "Trash" "silent"
    fi
    echo -e "${GREEN}  ✓ Trash Emptied${NC}"
fi

# --- 6. DEVELOPMENT TOOLS ---
echo ""
echo -e "${BLUE}${BOLD}=== Development Tools ===${NC}"
if ask "Clean development caches (Mobile, Node, Python, C++, Containers, etc)?"; then
    # C/C++ Compilation Caches
    clean_directory "$HOME/.cache/clangd" "Clangd (C/C++) Cache"
    if command -v ccache &> /dev/null; then
        echo -e "${YELLOW}Cleaning: ccache (Compiler Cache)${NC}"
        run ccache --clear
    fi
    if command -v sccache &> /dev/null; then
        # sccache -z only resets stats; stop the server and delete the storage
        run sccache --stop-server >/dev/null 2>&1
        clean_directory "$HOME/.cache/sccache" "sccache (Rust/C++ Compiler Cache)"
    fi

    # Rust / Cargo (registry/cache rebuilds src, git/db rebuilds checkouts)
    clean_directory "$HOME/.cargo/registry/cache" "Cargo Registry Cache"
    clean_directory "$HOME/.cargo/registry/src" "Cargo Registry Sources"
    clean_directory "$HOME/.cargo/git/checkouts" "Cargo Git Checkouts"

    # Mobile Ecosystem (Flutter, Android, Java)
    if command -v flutter &> /dev/null; then
        clean_directory "$HOME/.pub-cache/hosted" "Flutter Pub Cache"
    fi
    clean_directory "$HOME/.gradle/caches" "Gradle Caches"
    clean_directory "$HOME/.gradle/daemon" "Gradle Daemons"
    clean_directory "$HOME/.m2/repository" "Maven Repository"
    clean_directory "$HOME/.android/cache" "Android SDK Cache"

    # Electron
    clean_directory "$HOME/.cache/electron" "Electron Cache"
    clean_directory "$HOME/.cache/electron-builder" "Electron Builder Cache"

    # Bun
    if command -v bun &> /dev/null; then
        echo -e "${YELLOW}Cleaning: Bun Cache${NC}"
        run bun pm cache rm 2>/dev/null
    fi

    # Node / NPM / Yarn / pnpm
    if command -v npm &> /dev/null; then
        echo -e "${YELLOW}Cleaning: NPM Cache${NC}"
        run npm cache clean --force 2>/dev/null
    fi
    if command -v yarn &> /dev/null; then
        echo -e "${YELLOW}Cleaning: Yarn Cache${NC}"
        run yarn cache clean 2>/dev/null
    fi
    if command -v pnpm &> /dev/null; then
        echo -e "${YELLOW}Cleaning: pnpm Store (unreferenced packages)${NC}"
        run pnpm store prune
    fi

    # Go (build cache is the big one; downloaded modules are kept)
    if command -v go &> /dev/null; then
        echo -e "${YELLOW}Cleaning: Go Build Cache${NC}"
        run go clean -cache 2>/dev/null
    fi

    # Python
    if command -v pip &> /dev/null; then
        echo -e "${YELLOW}Cleaning: Pip Cache${NC}"
        run pip cache purge 2>/dev/null
    else
        clean_directory "$HOME/.cache/pip" "Pip Cache"
    fi
    if command -v uv &> /dev/null; then
        echo -e "${YELLOW}Cleaning: uv Cache (unused entries)${NC}"
        # uv crashes with hardened_malloc preloaded
        run env LD_PRELOAD= uv cache prune
    fi

    # Containers (docker here is the podman shim, so prune podman directly)
    if command -v podman &> /dev/null; then
        echo -e "${YELLOW}Podman: Pruning stopped containers, dangling images, build cache...${NC}"
        run podman system prune -f
    elif command -v docker &> /dev/null; then
        if systemctl is-active --quiet docker; then
            echo -e "${YELLOW}Docker: Pruning unused objects...${NC}"
            run docker system prune -f
            run docker builder prune -f
        else
            echo -e "${YELLOW}Docker: Daemon is not running, skipping prune.${NC}"
        fi
    fi
else
    echo "Skipping development tools."
fi

# --- 7. AI & MACHINE LEARNING (Ollama, ComfyUI) ---
echo ""
echo -e "${BLUE}${BOLD}=== AI & Machine Learning ===${NC}"
if ask "Clean AI temporary files (ComfyUI temp, HuggingFace datasets, PyCaches)?"; then
    # ComfyUI (git clone or ComfyUI Desktop base path)
    comfy_found=0
    for COMFYUI_DIR in "$HOME/ComfyUI" "$HOME/Documents/ComfyUI"; do
        [ -d "$COMFYUI_DIR" ] || continue
        comfy_found=1
        clean_directory "$COMFYUI_DIR/temp" "ComfyUI Temp/Latent Folder ($COMFYUI_DIR)"

        echo -e "${YELLOW}Cleaning: ComfyUI __pycache__ folders (will recompile on next run)${NC}"
        run find "$COMFYUI_DIR" -path "$COMFYUI_DIR/.venv" -prune -o \
            -type d -name "__pycache__" -exec rm -rf {} +
    done
    clean_directory "$HOME/.config/ComfyUI/logs" "ComfyUI Desktop Logs"
    [ "$comfy_found" -eq 0 ] && echo -e "  ${YELLOW}ComfyUI directory not found. Skipping...${NC}"

    clean_directory "$HOME/.cache/huggingface/datasets" "HuggingFace Datasets Cache"

    # Ollama: only touch its temp files when it is not running
    if pgrep -x ollama > /dev/null; then
        echo -e "  ${YELLOW}Ollama is running, skipping its /tmp files.${NC}"
    else
        ollama_tmp=(/tmp/ollama*)
        if [ ${#ollama_tmp[@]} -gt 0 ]; then
            echo -e "${YELLOW}Cleaning: Ollama temporary files${NC}"
            run sudo rm -rf "${ollama_tmp[@]}"
        fi
    fi
fi

# GPU shader caches (NVIDIA/Mesa/CUDA). Rebuilt on demand: first launches stutter a bit.
echo ""
echo -e "${BLUE}${BOLD}=== GPU Shader Caches ===${NC}"
if ask "Clean GPU shader caches (NVIDIA GL, Mesa, CUDA JIT)?"; then
    clean_directory "$HOME/.cache/nvidia/GLCache" "NVIDIA GL Shader Cache"
    clean_directory "$HOME/.cache/mesa_shader_cache" "Mesa Shader Cache"
    clean_directory "$HOME/.cache/mesa_shader_cache_db" "Mesa Shader Cache (DB)"
    clean_directory "$HOME/.nv/ComputeCache" "CUDA Compute (JIT) Cache"
fi

# --- 8. STALE CACHE SWEEP ---
# Catches programs not listed above (uninstalled or abandoned): a ~/.cache/<app>
# folder where no file was read in 90 days is deleted as a whole. Whole folders
# only, so structured caches (uv, paru clones, playwright...) are never left
# half-deleted. Root is mounted with relatime, so atime is reliable.
echo ""
echo -e "${BLUE}${BOLD}=== Stale Cache Sweep ===${NC}"
stale_dirs=()
for d in "$HOME/.cache"/*/; do
    d="${d%/}"
    case "${d##*/}" in
        huggingface|zellij) continue ;;  # models / saved sessions
    esac
    if [ -z "$(find "$d" -type f -atime -90 -print -quit 2>/dev/null)" ]; then
        stale_dirs+=("$d")
    fi
done
if [ ${#stale_dirs[@]} -gt 0 ]; then
    echo -e "${YELLOW}Cache folders unused for 90+ days:${NC}"
    for d in "${stale_dirs[@]}"; do
        echo -e "  - ${d#$HOME/} ($(du -sh "$d" 2>/dev/null | awk '{print $1}'))"
    done
    if ask "Delete them?"; then
        stale_freed=0
        for d in "${stale_dirs[@]}"; do
            clean_directory "$d" "$d" "silent"
            stale_freed=$((stale_freed + last_freed))
        done
        echo -e "${GREEN}  ✓ Freed: $(human "$stale_freed")${NC}"
    fi
else
    echo -e "  No stale cache folders."
fi

# --- 9. TEMPORARY FILES ---
echo ""
echo -e "${BLUE}${BOLD}=== Temporary Files ===${NC}"
echo -e "${YELLOW}Cleaning: Vim swap, backup (~) and valgrind core files${NC}"
# Single pass over $HOME. Skips heavy/app-managed trees and files touched in
# the last hour (a .swp that recent probably belongs to an open editor).
# Vim persistent undo (*.un~) is intentionally kept.
temp_files=$(find "$HOME" \
    \( -name .git -o -name node_modules -o -path "$HOME/.steam" -o -path "$HOME/.var" \
       -o -path "$HOME/.cache" -o -path "$HOME/Videos" -o -path "$HOME/.local/share/Steam" \
       -o -path "$HOME/.ollama" \) -prune -o \
    -type f \( -name '*.swp' -o -name '.*.swp' -o -name '*~' -o -name 'vgcore.*' \) \
    -mmin +60 -print 2>/dev/null)
if [ -n "$temp_files" ]; then
    temp_count=$(wc -l <<< "$temp_files")
    if [ "$DRY_RUN" -eq 1 ]; then
        sed 's/^/  [dry-run] rm /' <<< "$temp_files"
    else
        tr '\n' '\0' <<< "$temp_files" | xargs -0 rm -f
    fi
    echo -e "${GREEN}  ✓ Removed $temp_count file(s)${NC}"
    cleaned_count=$((cleaned_count + 1))
else
    echo -e "  No files found"
fi

# --- 10. BIG ITEMS REPORT (nothing is deleted here) ---
echo ""
echo -e "${BLUE}${BOLD}=== Big Items To Review Manually ===${NC}"
report_size() {
    local path="$1" label="$2" size
    [ -e "$path" ] || return 0
    size=$(du -sh "$path" 2>/dev/null | awk '{print $1}')
    echo -e "  ${BOLD}${size}${NC}\t${label} (${path#$HOME/})"
}
report_size "$HOME/.cache/huggingface/hub" "HuggingFace models"
report_size "$HOME/.ollama/models" "Ollama models (ollama list / ollama rm)"
report_size "$HOME/.local/share/containers" "Podman images/volumes (podman system df)"
report_size "$HOME/VirtualBox VMs" "VirtualBox VMs"
report_size "$HOME/.local/share/libvirt/images" "QEMU/libvirt disk images"
report_size "$HOME/.var/app/com.usebottles.bottles/data/bottles/bottles" "Bottles (Wine prefixes)"
report_size "$HOME/.local/share/sqlmap/output" "sqlmap scan output"
report_size "$HOME/Videos/CacheClip" "DaVinci CacheClip"

# --- 11. SUMMARY ---
echo ""
echo -e "${GREEN}${BOLD}=== Cleanup Completed! ===${NC}"
echo "User directories cleaned: $cleaned_count"

if [ "$DRY_RUN" -eq 1 ]; then
    echo -e "Would free (user caches, approx): ${GREEN}${BOLD}$(human "$total_freed_bytes")${NC}"
    echo "System caches (pacman, journal, flatpak...) not included in dry-run estimate."
else
    root_freed=$(( $(avail_bytes /) - root_avail_before ))
    echo -e "User caches cleaned: ${GREEN}${BOLD}$(human "$total_freed_bytes")${NC}"
    echo -e "Real free space gained on /: ${GREEN}${BOLD}$(human "$(( root_freed > 0 ? root_freed : 0 ))")${NC}"
    if [ -n "$home_mount" ] && [ "$home_mount" != "/" ]; then
        home_freed=$(( $(avail_bytes "$HOME") - home_avail_before ))
        echo -e "Real free space gained on $home_mount: ${GREEN}${BOLD}$(human "$(( home_freed > 0 ? home_freed : 0 ))")${NC}"
    fi
fi
echo -e "${BLUE}Have a productive day!${NC}"
echo ""
