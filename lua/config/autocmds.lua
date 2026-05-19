-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

vim.api.nvim_create_autocmd("TextYankPost", {
  desc = "Sync yanked text to system clipboard",
  callback = function()
    -- Only sync if the operator was 'y' (yank)
    -- This ignores 'd' (delete), 'c' (change), and 'x' (delete char)
    if vim.v.event.operator == "y" then
      vim.fn.setreg("+", vim.fn.getreg("0"))
    end
  end,
})

-- Warn when modifying files managed by Chezmoi
vim.api.nvim_create_autocmd("BufReadPost", {
  group = vim.api.nvim_create_augroup("ChezmoiWarn", { clear = true }),
  callback = function(event)
    -- 1. Ignore if we are already inside a 'chezmoi edit' session
    if vim.env.CHEZMOI then
      return
    end

    local filepath = vim.api.nvim_buf_get_name(event.buf)
    local home = vim.env.HOME

    -- 2. Fast Path: Only check files inside your home directory or .config
    if not filepath:find(home, 1, true) then
      return
    end

    -- Core function that handles the check and notification
    local function run_chezmoi_check()
      if not vim.api.nvim_buf_is_valid(event.buf) then
        return
      end

      if vim.fn.executable("chezmoi") == 1 then
        vim.fn.system({ "chezmoi", "source-path", filepath })

        if vim.v.shell_error == 0 then
          vim.bo[event.buf].readonly = true

          vim.notify(
            "This file is managed by Chezmoi!\nOpened as Read-Only. Edit source file instead.",
            vim.log.levels.WARN,
            {
              title = "Chezmoi Protector",
              timeout = false,
            }
          )
        end
      end
    end

    -- 3. Check if Neovim is still starting up
    -- vim.v.vim_did_enter is 0 during startup, and 1 after the UI is ready
    if vim.v.vim_did_enter == 0 then
      -- If starting up from CLI, wait for Lazy.nvim to finish loading plugins
      vim.api.nvim_create_autocmd("User", {
        pattern = "VeryLazy",
        once = true,
        callback = function()
          vim.schedule(run_chezmoi_check)
        end,
      })
    else
      -- If Neovim is already running (e.g. :e file), run it immediately
      vim.schedule(run_chezmoi_check)
    end
  end,
})
