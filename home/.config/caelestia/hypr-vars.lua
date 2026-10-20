-- Overrides of ~/.config/hypr/variables.lua (Caelestia updates
-- never touch this file). Caelestia's defaults point to apps that are not
-- installed here (foot, firefox, codium).
return {
    terminal        = "env LD_PRELOAD=/usr/lib/libhardened_malloc.so ghostty",
    browser         = "app.zen_browser.zen",
    editor          = "zeditor",
    -- Caelestia runs `hyprctl setcursor` with this at startup, which wins
    -- over the cursor env set by HyprMod. Lives in ~/.icons.
    cursorTheme     = "Bibata-Modern-Ice",
    -- No hibernation here (only zram swap): suspend-then-hibernate fails.
    sleepGestureCmd = "systemctl suspend",
    -- Outer gap with a single window on the monitor (Caelestia: 20);
    -- same as gaps_out in hyprland-gui.lua.
    singleWindowGapsOut = 8,
}
