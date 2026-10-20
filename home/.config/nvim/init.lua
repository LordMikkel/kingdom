vim.cmd("syntax on")
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.mouse = "a"
vim.opt.showmatch = true
vim.opt.wildmenu = true
vim.opt.incsearch = true
vim.opt.hlsearch = true
vim.opt.autoindent = true
vim.opt.smartindent = true
vim.opt.expandtab = false
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4

vim.keymap.set("i", "(", "()<Left>", { noremap = true })
vim.keymap.set("i", "[", "[]<Left>", { noremap = true })
vim.keymap.set("i", '"', '""<Left>', { noremap = true })
vim.keymap.set("i", "'", "''<Left>", { noremap = true })
vim.keymap.set("i", "{<CR>", "{<CR>}<Esc>O", { noremap = true })

-- Colors from caelestia (colors/caelestia.lua), follows the wallpaper
pcall(vim.cmd.colorscheme, "caelestia")
