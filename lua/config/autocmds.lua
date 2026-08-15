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

-- Warn when viewing Chezmoi destinations, and open the source in a split
do
  local DEST_NOTIF_ID = "chezmoi_protector"
  local DEST_HEIGHT = 7
  local group = vim.api.nvim_create_augroup("ChezmoiWarn", { clear = true })
  local chezmoi_ok = vim.fn.executable("chezmoi") == 1
  local source_root ---@type string|nil
  local inflight = 0
  local applying = false
  ---@type { buf: integer, source_path: string }[]
  local queued = {}
  local queued_set = {}
  ---@type snacks.win|nil
  local source_float

  local function hide_dest_warn()
    if Snacks and Snacks.notifier then
      Snacks.notifier.hide(DEST_NOTIF_ID)
    end
  end

  local function show_dest_warn()
    vim.notify(
      "This file is managed by Chezmoi\nOpened as Read-Only.\nEdit the source in the split below.",
      vim.log.levels.WARN,
      {
        id = DEST_NOTIF_ID,
        title = "Chezmoi Protector",
        timeout = false,
      }
    )
  end

  ---@param flag string
  ---@return integer|nil
  local function find_win_with_flag(flag)
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_config(win).relative == "" then
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(buf) and vim.b[buf][flag] then
          return win
        end
      end
    end
  end

  local function hide_source_info()
    if source_float then
      pcall(function()
        source_float:close()
      end)
      source_float = nil
    end
  end

  local function show_source_info()
    if applying or not (Snacks and Snacks.win) then
      return
    end
    local source_win = find_win_with_flag("chezmoi_is_source")
    if not source_win then
      hide_source_info()
      return
    end

    local title = "   Chezmoi Protector "
    local msg = "Chezmoi Source File"
    local width = math.max(vim.api.nvim_strwidth(title), vim.api.nvim_strwidth(msg) + 2)

    if source_float and source_float:win_valid() then
      source_float.opts.win = source_win
      source_float.opts.width = width
      source_float:update()
      return
    end

    source_float = Snacks.win({
      style = "notification",
      enter = false,
      backdrop = false,
      focusable = false,
      relative = "win",
      win = source_win,
      row = 0,
      col = -1,
      width = width,
      height = 1,
      border = true,
      title = title,
      title_pos = "center",
      text = msg,
      zindex = 100,
      wo = {
        winhighlight = "Normal:Normal,NormalNC:Normal,FloatBorder:DiagnosticOk,FloatTitle:DiagnosticOk",
      },
      bo = { filetype = "snacks_notif", buftype = "nofile", bufhidden = "wipe" },
      keys = { q = "close" },
      on_close = function()
        source_float = nil
      end,
    })
  end

  local function sync_chezmoi_warn()
    if find_win_with_flag("chezmoi_managed") then
      show_dest_warn()
    else
      hide_dest_warn()
    end
    if find_win_with_flag("chezmoi_is_source") then
      show_source_info()
    else
      hide_source_info()
    end
  end

  ---@param path string
  ---@param dir string|nil
  local function is_under(path, dir)
    if not dir or dir == "" then
      return false
    end
    dir = dir:gsub("/$", "")
    return path == dir or path:sub(1, #dir + 1) == dir .. "/"
  end

  local function get_source_root()
    if source_root ~= nil then
      return source_root
    end
    if not chezmoi_ok then
      source_root = ""
      return source_root
    end
    local result = vim.system({ "chezmoi", "source-path" }, { text = true }):wait()
    source_root = result.code == 0 and vim.trim(result.stdout or "") or ""
    return source_root
  end

  ---@param buf integer
  local function buf_path(buf)
    local name = vim.api.nvim_buf_get_name(buf)
    if name == "" then
      return ""
    end
    return vim.fn.fnamemodify(name, ":p")
  end

  ---@param win integer
  local function is_editor_win(win)
    if vim.api.nvim_win_get_config(win).relative ~= "" then
      return false
    end
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype ~= "" then
      return false
    end
    local ft = vim.bo[buf].filetype
    return ft ~= "neo-tree" and ft ~= "snacks_layout_box" and ft ~= "minifiles" and ft ~= "oil"
  end

  ---@param dest_buf integer
  ---@param source_path string
  local function prepare_companion(dest_buf, source_path)
    local source_buf = vim.fn.bufadd(source_path)
    vim.bo[source_buf].buflisted = false
    vim.bo[source_buf].bufhidden = "hide"
    vim.b[source_buf].chezmoi_is_source = true
    vim.b[dest_buf].chezmoi_companion = source_buf
    vim.b[dest_buf].chezmoi_source_path = source_path
    return source_buf
  end

  ---@param dest_buf integer
  ---@param opts? { focus_source?: boolean }
  ---@return integer|nil source_win
  local function layout_pair(dest_buf, opts)
    opts = opts or {}
    if applying or not vim.api.nvim_buf_is_valid(dest_buf) then
      return
    end

    local source_buf = vim.b[dest_buf].chezmoi_companion
    if not source_buf or not vim.api.nvim_buf_is_valid(source_buf) then
      local source_path = vim.b[dest_buf].chezmoi_source_path
      if not source_path then
        return
      end
      source_buf = prepare_companion(dest_buf, source_path)
    end
    vim.bo[source_buf].buflisted = false

    local tab = vim.api.nvim_get_current_tabpage()
    local dest_win, source_win
    local editors = {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
      if is_editor_win(win) then
        editors[#editors + 1] = win
        local buf = vim.api.nvim_win_get_buf(win)
        if buf == dest_buf then
          dest_win = win
        elseif buf == source_buf then
          source_win = win
        end
      end
    end

    -- Already showing this dest/source pair: keep the user's focus
    if dest_win and source_win then
      if opts.focus_source then
        vim.api.nvim_set_current_win(source_win)
      end
      return source_win
    end

    local function set_buf(win, buf)
      local shortmess = vim.o.shortmess
      vim.o.shortmess = shortmess .. "A"
      local ok, err = pcall(vim.api.nvim_win_set_buf, win, buf)
      vim.o.shortmess = shortmess
      if not ok then
        error(err)
      end
    end

    applying = true
    local ok, err = pcall(function()
      table.sort(editors, function(a, b)
        return vim.api.nvim_win_get_position(a)[1] < vim.api.nvim_win_get_position(b)[1]
      end)

      if #editors >= 2 then
        dest_win = editors[1]
        source_win = editors[2]
        set_buf(dest_win, dest_buf)
        set_buf(source_win, source_buf)
      else
        dest_win = dest_win or vim.api.nvim_get_current_win()
        vim.api.nvim_set_current_win(dest_win)
        set_buf(dest_win, dest_buf)
        vim.cmd("belowright split")
        source_win = vim.api.nvim_get_current_win()
        set_buf(source_win, source_buf)
      end

      if dest_win and vim.api.nvim_win_is_valid(dest_win) then
        vim.api.nvim_win_set_height(dest_win, DEST_HEIGHT)
        vim.wo[dest_win].winfixheight = true
      end

      vim.bo[source_buf].buflisted = false
      if opts.focus_source ~= false then
        vim.api.nvim_set_current_win(source_win)
      end
    end)
    applying = false
    if not ok then
      return
    end
    return source_win
  end

  local function apply_layout()
    if applying or inflight > 0 or #queued == 0 then
      return
    end

    local items = queued
    queued = {}
    queued_set = {}

    local origin_buf = vim.api.nvim_get_current_buf()
    for _, item in ipairs(items) do
      prepare_companion(item.buf, item.source_path)
    end

    -- Only the visible dest gets a split. Other dests stay listed so they
    -- share the tabline; switching to one swaps this same dest/source pair.
    if vim.api.nvim_buf_is_valid(origin_buf) and vim.b[origin_buf].chezmoi_managed then
      layout_pair(origin_buf, { focus_source = true })
    end

    sync_chezmoi_warn(vim.api.nvim_get_current_buf())
  end

  ---@param buf integer
  ---@param source_path string
  local function enqueue(buf, source_path)
    if queued_set[buf] or vim.b[buf].chezmoi_companion then
      return
    end
    queued_set[buf] = true
    queued[#queued + 1] = { buf = buf, source_path = source_path }
  end

  ---@param buf integer
  local function should_check(buf)
    if not chezmoi_ok or vim.env.CHEZMOI or applying then
      return false
    end
    if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
      return false
    end
    if vim.bo[buf].buftype ~= "" then
      return false
    end
    if vim.b[buf].chezmoi_managed or vim.b[buf].chezmoi_is_source or vim.b[buf].chezmoi_companion then
      return false
    end

    local filepath = buf_path(buf)
    if filepath == "" then
      return false
    end
    if not is_under(filepath, vim.env.HOME) then
      return false
    end
    if is_under(filepath, get_source_root()) then
      return false
    end
    return true
  end

  ---@param buf integer
  local function consider_buf(buf)
    if not should_check(buf) then
      return
    end

    inflight = inflight + 1
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) and should_check(buf) then
        local filepath = buf_path(buf)
        local result = vim.system({ "chezmoi", "source-path", filepath }, { text = true }):wait()
        if result.code == 0 then
          local source_path = vim.trim(result.stdout or "")
          if source_path ~= "" and source_path ~= filepath then
            vim.bo[buf].readonly = true
            vim.b[buf].chezmoi_managed = true
            enqueue(buf, source_path)
            if buf == vim.api.nvim_get_current_buf() then
              sync_chezmoi_warn()
            end
          end
        end
      end

      inflight = inflight - 1
      if inflight == 0 then
        apply_layout()
      end
    end)
  end

  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group = group,
    callback = function(event)
      sync_chezmoi_warn(event.buf)
      if applying or event.event ~= "BufEnter" then
        return
      end
      if vim.api.nvim_buf_is_valid(event.buf) and vim.b[event.buf].chezmoi_managed then
        layout_pair(event.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    callback = function(event)
      local source_buf = vim.b[event.buf].chezmoi_companion
      if source_buf and vim.api.nvim_buf_is_valid(source_buf) and not vim.bo[source_buf].buflisted then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(source_buf) then
            pcall(vim.api.nvim_buf_delete, source_buf, { force = true })
          end
        end)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufReadPost", {
    group = group,
    callback = function(event)
      consider_buf(event.buf)
    end,
  })

  -- Autocmds load on VeryLazy, after the first startup file was already read.
  -- Other argv files exist as unloaded buffers; load them so they get tabs too.
  vim.schedule(function()
    for _, arg in ipairs(vim.fn.argv()) do
      local buf = vim.fn.bufnr(arg)
      if buf > 0 and not vim.api.nvim_buf_is_loaded(buf) then
        pcall(vim.fn.bufload, buf)
      end
    end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      consider_buf(buf)
    end
  end)
end
