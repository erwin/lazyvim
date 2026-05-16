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
    -- This stops Vim from lagging when opening system files (/etc/) or project repos
    if not filepath:find(home, 1, true) then
      return
    end

    -- 3. Run the source-path check asynchronously/lightly via vim.fn.system
    if vim.fn.executable("chezmoi") == 1 then
      vim.fn.system({ "chezmoi", "source-path", filepath })

      -- If exit code is 0, the file is tracked by chezmoi
      if vim.v.shell_error == 0 then
        -- Force the file to be Read-Only to protect it
        vim.bo[event.buf].readonly = true

        -- Throw a gorgeous LazyVim notification
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
  end,
})
