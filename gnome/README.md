# GNOME settings

dconf snapshots of the GNOME desktop, loaded by the installer.

| File | Content |
|---|---|
| `desktop.dconf` | interface, theme, fonts, input, WM keybindings |
| `shell.dconf` | shell, favorites, extension settings |
| `mutter.dconf` | window manager / workspaces |
| `settings-daemon.dconf` | custom keybindings, power, media keys |
| `extensions-*.txt` | installed / enabled extensions |
| `dconf-full.local.dconf` | full dump, **git-ignored** (contains private paths) |

Scripts (run as your user, not root):

```sh
~/dotfiles/scripts/pull-gnome.sh     # live dconf -> gnome/
~/dotfiles/scripts/status-gnome.sh   # diff gnome/ vs live
~/dotfiles/scripts/install-gnome.sh  # gnome/ -> dconf (with backup)
```

Restore one area by hand (example):

```sh
dconf load /org/gnome/shell/ < ~/dotfiles/gnome/shell.dconf
```
