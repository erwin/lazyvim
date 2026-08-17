-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Navigate buffers in visual order. Dest preview is unlisted, so cycle from
-- its source tab when focus is in the destination pane.
local function bufferline_cycle(dir)
  local buf = vim.api.nvim_get_current_buf()
  if vim.b[buf].chezmoi_managed then
    local source = vim.b[buf].chezmoi_companion
    if source then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_buf(win) == source then
          vim.api.nvim_set_current_win(win)
          break
        end
      end
    end
  end
  vim.cmd(dir > 0 and "BufferLineCycleNext" or "BufferLineCyclePrev")
end

vim.keymap.set("n", "<Tab>", function()
  bufferline_cycle(1)
end, { desc = "Next Buffer" })
vim.keymap.set("n", "<S-Tab>", function()
  bufferline_cycle(-1)
end, { desc = "Prev Buffer" })
vim.keymap.set({ "n", "x" }, "j", 'v:count == 0 ? "gj" : "j"', { expr = true, silent = true })
vim.keymap.set({ "n", "x" }, "k", 'v:count == 0 ? "gk" : "k"', { expr = true, silent = true })
