-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.opt.clipboard = "" -- Reset to default (internal registers only)

-- TextYankPost uses setreg("+", ...), which needs a working clipboard backend.
-- Without this, Neovim may pick xsel via DISPLAY=:0 and fail with "BadAccess" on Wayland/SSH.
if vim.env.SSH_CONNECTION or vim.env.SSH_TTY then
  vim.g.clipboard = "osc52"
elseif vim.env.WAYLAND_DISPLAY and vim.fn.executable("wl-copy") == 1 then
  vim.g.clipboard = "wl-copy"
elseif vim.env.DISPLAY and vim.fn.executable("xclip") == 1 then
  vim.g.clipboard = "xclip"
end
