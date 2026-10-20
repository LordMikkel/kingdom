-- Hyprland settings on top of Caelestia (loaded after its config
-- by ~/.config/hypr/hyprland.lua). Caelestia updates never touch this file.
-- Check it before saving: Hyprland --verify-config -c ~/.config/hypr/hyprland.lua

-- Monitors: Hyprland gives each one its preferred mode and places them
-- left to right. To set them by hand, list them with: hyprctl monitors all

-- CTRL+SUPER+Left/Right switch workspaces on the focused monitor, skipping
-- those that live on another monitor (Caelestia's +1/-1 jumped to them).
hl.unbind("CTRL + SUPER + Left")
hl.unbind("CTRL + SUPER + Right")
hl.bind("CTRL + SUPER + Left",  hl.dsp.focus({ workspace = "r-1" }), { repeating = true })
hl.bind("CTRL + SUPER + Right", hl.dsp.focus({ workspace = "r+1" }), { repeating = true })

-- Same for SUPER+Page_Up/Down and SUPER+wheel, and for moving the window
-- with SUPER+ALT (+ CTRL+SUPER+SHIFT+Left/Right).
for _, b in ipairs({
    { "SUPER + Page_Up",               hl.dsp.focus({ workspace = "r-1" }),       true },
    { "SUPER + Page_Down",             hl.dsp.focus({ workspace = "r+1" }),       true },
    { "SUPER + mouse_up",              hl.dsp.focus({ workspace = "r-1" }),       false },
    { "SUPER + mouse_down",            hl.dsp.focus({ workspace = "r+1" }),       false },
    { "SUPER + ALT + Page_Up",         hl.dsp.window.move({ workspace = "r-1" }), true },
    { "SUPER + ALT + Page_Down",       hl.dsp.window.move({ workspace = "r+1" }), true },
    { "SUPER + ALT + mouse_up",        hl.dsp.window.move({ workspace = "r-1" }), false },
    { "SUPER + ALT + mouse_down",      hl.dsp.window.move({ workspace = "r+1" }), false },
    { "CTRL + SUPER + SHIFT + Left",   hl.dsp.window.move({ workspace = "r-1" }), true },
    { "CTRL + SUPER + SHIFT + Right",  hl.dsp.window.move({ workspace = "r+1" }), true },
}) do
    hl.unbind(b[1])
    hl.bind(b[1], b[2], { repeating = b[3] })
end

-- GNOME resets the shared GTK theme, icons and gtk.css at its login
-- (~/Scripts/session-theme.sh); put Caelestia's look back here.
hl.on("hyprland.start", function()
    hl.exec_cmd(os.getenv("HOME") .. "/Scripts/session-theme.sh hyprland")
end)

-- Tray icons back after a Caelestia shell restart (Proton VPN does not
-- register its icon again by itself): ~/Scripts/tray-reregister.sh.
hl.on("hyprland.start", function()
    hl.exec_cmd(os.getenv("HOME") .. "/Scripts/tray-reregister.sh")
end)

-- Keyboard layouts, same as GNOME: English (US) and Spanish.
hl.config({ input = { kb_layout = "us,es" } })

-- Our own keybinds live in ~/.config/hypr/hyprland-gui.lua so HyprMod lists
-- them as editable: SUPER+A code agents (agent-ghostty.sh), SUPER+Space next
-- keyboard layout, SUPER+O Caelestia settings (Nexus), CTRL+SHIFT+Space
-- voxtype dictation (~/Scripts/dictate.sh keeps the mic muted otherwise).

-- Empty submap voxtype enters while it pastes (pre/post_output_command in
-- ~/.config/voxtype/config.toml). wtype's virtual key reaches Hyprland as
-- Escape, so CTRL+SHIFT+V turned into CTRL+SHIFT+Escape and opened btop.
-- SUPER+Escape leaves it by hand if voxtype ever fails to reset it.
hl.define_submap("voxtype_suppress", function()
    hl.bind("SUPER + Escape", hl.dsp.submap("reset"))
end)

-- HyprMod settings and our keybinds (~/.config/hypr/hyprland-gui.lua) load
-- from the include line HyprMod adds to Caelestia's hyprland.lua. A Caelestia
-- update that replaces hyprland.lua drops that line: load the file from here
-- until HyprMod's onboarding adds it back, so it never loads twice.
do
    local hypr = os.getenv("HOME") .. "/.config/hypr/"
    local f = io.open(hypr .. "hyprland.lua")
    local entry = f and f:read("*a") or ""
    if f then f:close() end
    if not entry:find('require("hyprland-gui")', 1, true) then
        dofile(hypr .. "hyprland-gui.lua")
    end
end
