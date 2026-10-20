# ============================================================================
#                                   Shell                                    #
# ============================================================================

# Prompt
autoload -Uz promptinit
promptinit
prompt adam1

# Emacs keybindings, even if EDITOR is vi
bindkey -e

# History
setopt histignorealldups sharehistory
HISTSIZE=1000
SAVEHIST=1000
HISTFILE=~/.zsh_history

# ============================================================================
#                                 Completion                                 #
# ============================================================================

autoload -Uz compinit
compinit

eval "$(dircolors -b)"
zstyle ':completion:*' auto-description 'specify: %d'
zstyle ':completion:*' completer _expand _complete _correct _approximate
zstyle ':completion:*' format 'Completing %d'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' menu select=long
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' list-prompt %SAt %p: Hit TAB for more, or the character to insert%s
zstyle ':completion:*' matcher-list '' 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=* l:|=*'
zstyle ':completion:*' select-prompt %SScrolling active: current selection at %p%s
zstyle ':completion:*' use-compctl false
zstyle ':completion:*' verbose true
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'

# ============================================================================
#                                  Plugins                                   #
# ============================================================================

# Powerlevel10k (disabled)
# if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
#  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
# fi
# if [[ -r "/usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme" ]]; then
#    source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme
# fi
# [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Autosuggestions (disabled)
# if [ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]; then
#    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
# fi

# Syntax highlighting
if [ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]; then
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

# zoxide
eval "$(zoxide init zsh)"

# thefuck
eval "$(thefuck --alias)"

# ============================================================================
#                                   Colors                                   #
# ============================================================================

# Syntax highlighting colors
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern cursor)
typeset -A ZSH_HIGHLIGHT_STYLES

# Commands
ZSH_HIGHLIGHT_STYLES[command]='fg=#D7BB6C,bold'
ZSH_HIGHLIGHT_STYLES[alias]='fg=#D7BB6C,bold'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=#D7BB6C,bold'
ZSH_HIGHLIGHT_STYLES[function]='fg=#D7BB6C,bold'
ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=#D7BB6C,bold'

# Sudo
ZSH_HIGHLIGHT_STYLES[precommand]='fg=#99b3c6,bold'

# Errors
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#b0b0b0'

# Paths
ZSH_HIGHLIGHT_STYLES[path]='fg=#999999'
ZSH_HIGHLIGHT_STYLES[path_prefix]='fg=#999999'

# Flags
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=#D7BB6C,bold'
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=#D7BB6C,bold'

# Variables and expansions
ZSH_HIGHLIGHT_STYLES[variable]='fg=#e0e0e0,bold'
ZSH_HIGHLIGHT_STYLES[expansion]='fg=#e0e0e0,bold'
ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]='fg=#e0e0e0,bold'
ZSH_HIGHLIGHT_STYLES[back-dollar-quoted-argument]='fg=#e0e0e0,bold'
ZSH_HIGHLIGHT_STYLES[assign]='fg=#e0e0e0'

# Operators
ZSH_HIGHLIGHT_STYLES[redirection]='fg=#a38ede'
ZSH_HIGHLIGHT_STYLES[command-separator]='fg=#a38ede'
ZSH_HIGHLIGHT_STYLES[process-substitution]='fg=#a38ede'

# Arguments
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#b0b0b0'
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#b0b0b0'
ZSH_HIGHLIGHT_STYLES[back-quoted-argument]='fg=#b0b0b0'
ZSH_HIGHLIGHT_STYLES[default]='fg=#b0b0b0'

# Extras
ZSH_HIGHLIGHT_STYLES[cursor]='bold'
ZSH_HIGHLIGHT_STYLES[history-expansion]='fg=#bbbbbb,bold'

# Themes
#export LS_COLORS="$(vivid generate catppuccin-macchiato)"
export BAT_THEME="Catppuccin Macchiato"

# Man pages with bat
export MANPAGER="sh -c 'col -bx | bat -l man -p'"
export MANROFFOPT="-c"

# ============================================================================
#                                Environment                                 #
# ============================================================================

# Editor
export EDITOR=vim
export VISUAL=vim

# PATH
export PATH="$HOME/.local/bin:$PATH"
export PATH="$PATH:$HOME/.local/share/gem/ruby/3.4.0/bin"

# CUDA
if [ -d "/opt/cuda" ]; then
    export CUDA_HOME="/opt/cuda"
    export PATH="$PATH:$CUDA_HOME/bin"
    export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$CUDA_HOME/lib64"
fi

# Sanitizer and valgrind suppressions
export LSAN_OPTIONS="suppressions=$HOME/.config/suppresion/sanitize_leaks.supp"
export TSAN_OPTIONS="suppressions=$HOME/.config/suppresion/sanitize_threads.supp"
export VALGRIND_OPTS="--suppressions=$HOME/.config/suppresion/valgrind_leaks.supp"

# Browser for Flutter
export CHROME_EXECUTABLE="$HOME/.local/bin/vivaldi-flutter"

# Secrets (outside dotfiles)
[ -f ~/.config/zsh/local.zsh ] && source ~/.config/zsh/local.zsh

# ============================================================================
#                                   Hooks                                    #
# ============================================================================

# Save the current dir
precmd() {
    echo -n $(pwd) > ~/.last_dir
}

# Open in the last dir, unless Files opens a specific folder
if [ -z "$GHOSTTY_OPENED_FROM_FILES" ] && [ -f ~/.last_dir ]; then
    cd "$(cat ~/.last_dir)"
fi

# ============================================================================
#                                  Aliases                                   #
# ============================================================================

# ls
alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias tree='eza --tree'

# cat with bat
if command -v bat >/dev/null; then
    alias cat='bat --style=plain --paging=never'
    alias catp='bat --style=numbers,changes'
fi

# Colors
alias grep='grep --color=auto'
alias diff='diff --color=auto'

# Faster replacements
alias grep=rg
alias find=fd
alias python=python3

# Colors with grc
alias ip='grc --colour=auto ip'
alias ping='grc --colour=auto ping'
alias ps='grc --colour=auto ps'
alias netstat='grc --colour=auto netstat'
alias dig='grc --colour=auto dig'
alias traceroute='grc --colour=auto traceroute'
alias head='grc --colour=auto head'
alias tail='grc --colour=auto tail'
alias ss='grc --colour=auto ss'
alias nmap='grc --colour=auto nmap'

# System
alias update='sudo pacman -Syu'
alias paru='LD_PRELOAD="" paru'
alias makepkg='LD_PRELOAD="" makepkg'
alias fix-pacman-eu='~/Scripts/fix-pacman.sh ES,FR,DE,CH,NL,PT,IT'
alias fix-pacman-am='~/Scripts/fix-pacman.sh US,CA,BR,MX,CL,AR,CO'
alias fix-pacman-as='~/Scripts/fix-pacman.sh JP,SG,KR,TW,HK,IN,ID,TH,VN'
alias fix-pacman-af='~/Scripts/fix-pacman.sh ZA,KE,MA'
alias fix-pacman-oc='~/Scripts/fix-pacman.sh AU,NZ'
alias clean='~/Scripts/cleaner-arch-linux.sh'
alias scanvirus='~/Scripts/scanvirus.sh'
alias dotsync='~/Scripts/dotsync.sh'
alias open='~/Scripts/open.sh'

# Network and Tor
alias ports='nmap -sT localhost'
alias connections='ss -tulpn'
alias by-tor='proxychains'
alias check-tor='~/Scripts/check-tor.sh'

# Development

# C
alias ccc='cc -Wall -Wextra -Werror'

# Valgrind
alias leaks='valgrind --leak-check=full --show-leak-kinds=definite,indirect,possible --track-origins=yes'
alias all-leaks='valgrind --leak-check=full --show-leak-kinds=all --track-origins=yes'
alias watch-mem='~/Scripts/watch-mem.sh'

# Opengrep
alias opengrep-c='opengrep scan --config ~/.config/opengrep/semgrep-rules/c'
alias opengrep-cpp='opengrep scan --config ~/.config/opengrep/semgrep-rules/cpp'
alias opengrep-bash='opengrep scan --config ~/.config/opengrep/semgrep-rules/bash'
alias opengrep-py='opengrep scan --config ~/.config/opengrep/semgrep-rules/python'
alias opengrep-ts='opengrep scan --config ~/.config/opengrep/semgrep-rules/typescript'
alias opengrep-rust='opengrep scan --config ~/.config/opengrep/semgrep-rules/rust'
alias opengrep-all='opengrep scan --config ~/.config/opengrep/semgrep-rules/'

# Languages
alias go='GOPATH=$HOME/.local/share/go go'
alias uv='LD_PRELOAD="" uv'


# Isolated container in the current dir
alias podsafe='podman run --rm -it --network=none --cap-drop=ALL --security-opt=no-new-privileges --read-only --tmpfs /tmp:exec -v "$PWD":/src:Z -w /src'

# Apps

# Flatpak
alias libreoffice='flatpak run org.libreoffice.LibreOffice'
alias session='flatpak run network.loki.Session'
alias vivaldi='flatpak run com.vivaldi.Vivaldi'
alias signal='flatpak run org.signal.Signal'
alias vlc='flatpak run org.videolan.VLC'
alias mullvad='flatpak run net.mullvad.MullvadBrowser'

# hardened_malloc on
alias ghostty='LD_PRELOAD=/usr/lib/libhardened_malloc.so ghostty'

# hardened_malloc off
alias code='LD_PRELOAD="" /usr/bin/code'
alias virt-manager='LD_PRELOAD="" virt-manager'

# Others
alias tor-browser='torbrowser-launcher'
alias zed='zeditor'
alias prime-chromium='~/Scripts/prime-chromium.sh'
alias conv-audio='~/Scripts/conv-audio.sh'

# VMs and services
alias virman-qemu='virsh -c qemu:///system'
alias kali='~/Scripts/kali.sh'
alias n8n='~/Scripts/n8n.sh'
