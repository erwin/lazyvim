-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Navigate buffers in visual order
vim.keymap.set("n", "<Tab>", "<cmd>BufferLineCycleNext<cr>", { desc = "Next Buffer" })
vim.keymap.set("n", "<S-Tab>", "<cmd>BufferLineCyclePrev<cr>", { desc = "Prev Buffer" })
vim.keymap.set({ "n", "x" }, "j", 'v:count == 0 ? "gj" : "j"', { expr = true, silent = true })
vim.keymap.set({ "n", "x" }, "k", 'v:count == 0 ? "gk" : "k"', { expr = true, silent = true })

-- Optional: If you want Tab to still work for completion in insert mode,
-- ensure these are only mapped for Normal mode ("n").
