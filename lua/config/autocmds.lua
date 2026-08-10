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

-- Warn when viewing files managed by Chezmoi (one sticky notif for the current buffer)
do
  local NOTIF_ID = "chezmoi_protector"
  local group = vim.api.nvim_create_augroup("ChezmoiWarn", { clear = true })

  local function show_chezmoi_warn()
    vim.notify(
      "This file is managed by Chezmoi!\nOpened as Read-Only. Edit source file instead.",
      vim.log.levels.WARN,
      {
        id = NOTIF_ID,
        title = "Chezmoi Protector",
        timeout = false,
      }
    )
  end

  local function hide_chezmoi_warn()
    if Snacks and Snacks.notifier then
      Snacks.notifier.hide(NOTIF_ID)
    end
  end

  local function sync_chezmoi_warn(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].chezmoi_managed then
      show_chezmoi_warn()
    else
      hide_chezmoi_warn()
    end
  end

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(event)
      sync_chezmoi_warn(event.buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufReadPost", {
    group = group,
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

      local function run_chezmoi_check()
        if not vim.api.nvim_buf_is_valid(event.buf) then
          return
        end

        if vim.fn.executable("chezmoi") == 1 then
          vim.fn.system({ "chezmoi", "source-path", filepath })

          if vim.v.shell_error == 0 then
            vim.bo[event.buf].readonly = true
            vim.b[event.buf].chezmoi_managed = true

            -- Only surface the sticky warning if this buffer is still focused
            if event.buf == vim.api.nvim_get_current_buf() then
              show_chezmoi_warn()
            end
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
end
