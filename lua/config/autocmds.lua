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

-- Chezmoi protector: opening a destination opens the source as the tab
-- (top, editable) with the destination as a read-only preview underneath.
do
  local DEST_HEIGHT = 7
  local group = vim.api.nvim_create_augroup("ChezmoiWarn", { clear = true })
  local chezmoi_ok = vim.fn.executable("chezmoi") == 1
  local source_root ---@type string|nil
  local inflight = 0
  local applying = false
  local closing_pair = false
  ---@type { buf: integer, source_path: string }[]
  local queued = {}
  local queued_set = {}
  ---@type snacks.win|nil
  local source_float
  ---@type snacks.win|nil
  local dest_float
  local DEST_WARN_TITLE = "   Chezmoi Protector "
  local DEST_WARN_MSG = "This file is managed by Chezmoi\nOpened as Read-Only.\nEdit the source in the split above."

  ---@param flag string
  ---@return integer|nil
  local function find_win_with_flag(flag)
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == "" then
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(buf) and vim.b[buf][flag] then
          return win
        end
      end
    end
  end

  ---@param float snacks.win|nil
  local function close_float(float)
    if float then
      pcall(function()
        float:close()
      end)
    end
  end

  local function hide_dest_warn()
    close_float(dest_float)
    dest_float = nil
    if Snacks and Snacks.notifier then
      Snacks.notifier.hide("chezmoi_protector")
    end
  end

  local function hide_source_info()
    close_float(source_float)
    source_float = nil
  end

  ---@param existing snacks.win|nil
  ---@param target_win integer
  ---@param spec { title: string, msg: string, height: integer, border_hl: string, on_close: fun() }
  ---@return snacks.win|nil
  local function show_pane_float(existing, target_win, spec)
    if applying or not (Snacks and Snacks.win) or not vim.api.nvim_win_is_valid(target_win) then
      return existing
    end
    local width = vim.api.nvim_strwidth(spec.title)
    for line in spec.msg:gmatch("[^\n]+") do
      width = math.max(width, vim.api.nvim_strwidth(line) + 2)
    end
    if existing and existing:win_valid() then
      existing.opts.win = target_win
      existing.opts.width = width
      existing.opts.height = spec.height
      pcall(function()
        existing:update()
      end)
      return existing
    end
    local ok, win = pcall(Snacks.win, {
      style = "notification",
      enter = false,
      backdrop = false,
      focusable = false,
      relative = "win",
      win = target_win,
      row = 0,
      col = -1,
      width = width,
      height = spec.height,
      border = true,
      title = spec.title,
      title_pos = "center",
      text = spec.msg,
      zindex = 100,
      wo = {
        winhighlight = "Normal:Normal,NormalNC:Normal,FloatBorder:"
          .. spec.border_hl
          .. ",FloatTitle:"
          .. spec.border_hl,
      },
      bo = { filetype = "snacks_notif", buftype = "nofile", bufhidden = "wipe" },
      keys = { q = "close" },
      on_close = spec.on_close,
    })
    if ok then
      return win
    end
    return existing
  end

  local function show_dest_warn()
    local dest_win = find_win_with_flag("chezmoi_managed")
    if not dest_win then
      hide_dest_warn()
      return
    end
    dest_float = show_pane_float(dest_float, dest_win, {
      title = DEST_WARN_TITLE,
      msg = DEST_WARN_MSG,
      height = 3,
      border_hl = "DiagnosticWarn",
      on_close = function()
        dest_float = nil
      end,
    })
  end

  local function show_source_info()
    local source_win = find_win_with_flag("chezmoi_is_source")
    if not source_win then
      hide_source_info()
      return
    end
    source_float = show_pane_float(source_float, source_win, {
      title = "   Chezmoi Protector ",
      msg = "Chezmoi Source File",
      height = 1,
      border_hl = "DiagnosticOk",
      on_close = function()
        source_float = nil
      end,
    })
  end

  local function sync_chezmoi_warn()
    if applying or closing_pair then
      return
    end
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
    if not vim.api.nvim_win_is_valid(win) then
      return false
    end
    local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
    if not ok or cfg.relative ~= "" then
      return false
    end
    local buf = vim.api.nvim_win_get_buf(win)
    if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
      return false
    end
    local ft = vim.bo[buf].filetype
    return ft ~= "neo-tree" and ft ~= "snacks_layout_box" and ft ~= "minifiles" and ft ~= "oil"
  end

  ---@param win integer
  ---@param buf integer
  local function set_buf(win, buf)
    local shortmess = vim.o.shortmess
    vim.o.shortmess = shortmess .. "A"
    local ok, err = pcall(vim.api.nvim_win_set_buf, win, buf)
    vim.o.shortmess = shortmess
    if not ok then
      error(err)
    end
  end

  ---@param dest_win integer
  local function size_dest(dest_win)
    if not vim.api.nvim_win_is_valid(dest_win) then
      return
    end
    vim.wo[dest_win].winfixheight = false
    pcall(vim.api.nvim_win_set_height, dest_win, DEST_HEIGHT)
    vim.wo[dest_win].winfixheight = true
  end

  ---@param dest_buf integer
  ---@param source_path string
  local function prepare_companion(dest_buf, source_path)
    local source_buf = vim.fn.bufadd(source_path)
    pcall(vim.fn.bufload, source_buf)
    vim.bo[source_buf].buflisted = true
    vim.bo[source_buf].bufhidden = "hide"
    vim.b[source_buf].chezmoi_is_source = true
    vim.b[source_buf].chezmoi_dest = dest_buf
    vim.b[source_buf].chezmoi_dest_path = buf_path(dest_buf)
    vim.b[dest_buf].chezmoi_companion = source_buf
    vim.b[dest_buf].chezmoi_source_path = source_path
    vim.bo[dest_buf].readonly = true
    return source_buf
  end

  ---@param buf integer
  ---@return integer|nil dest_buf
  ---@return integer|nil source_buf
  local function pair_for(buf)
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    if vim.b[buf].chezmoi_managed then
      return buf, vim.b[buf].chezmoi_companion
    end
    if vim.b[buf].chezmoi_is_source then
      local dest = vim.b[buf].chezmoi_dest
      if dest and vim.api.nvim_buf_is_valid(dest) then
        return dest, buf
      end
    end
  end

  ---@param dest_buf integer
  ---@param opts? { focus_source?: boolean }
  ---@return integer|nil source_win
  local function layout_pair(dest_buf, opts)
    opts = opts or {}
    if applying or closing_pair or not vim.api.nvim_buf_is_valid(dest_buf) then
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
    vim.bo[source_buf].buflisted = true

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

    applying = true
    local ok = pcall(function()
      if dest_win and source_win then
        if vim.api.nvim_win_get_position(dest_win)[1] < vim.api.nvim_win_get_position(source_win)[1] then
          set_buf(source_win, dest_buf)
          set_buf(dest_win, source_buf)
          dest_win, source_win = source_win, dest_win
        end
        size_dest(dest_win)
        vim.wo[source_win].winfixheight = false
      else
        table.sort(editors, function(a, b)
          return vim.api.nvim_win_get_position(a)[1] < vim.api.nvim_win_get_position(b)[1]
        end)

        if #editors >= 2 then
          source_win = editors[1]
          dest_win = editors[2]
          set_buf(source_win, source_buf)
          set_buf(dest_win, dest_buf)
        else
          source_win = vim.api.nvim_get_current_win()
          vim.api.nvim_set_current_win(source_win)
          vim.wo[source_win].winfixheight = false
          set_buf(source_win, source_buf)
          vim.cmd("belowright split")
          dest_win = vim.api.nvim_get_current_win()
          set_buf(dest_win, dest_buf)
        end

        size_dest(dest_win)
        if source_win and vim.api.nvim_win_is_valid(source_win) then
          vim.wo[source_win].winfixheight = false
        end
      end

      vim.bo[source_buf].buflisted = true
      vim.bo[dest_buf].buflisted = false
      vim.bo[dest_buf].bufhidden = "hide"
      if opts.focus_source ~= false and source_win and vim.api.nvim_win_is_valid(source_win) then
        vim.api.nvim_set_current_win(source_win)
      end
    end)
    applying = false
    if not ok then
      return
    end
    return source_win
  end

  ---@param exclude table<integer, boolean>
  ---@return integer|nil
  local function next_listed_except(exclude)
    for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
      local b = info.bufnr
      if not exclude[b] then
        local ok, bt = pcall(function()
          return vim.bo[b].buftype
        end)
        if ok and bt == "" and not vim.b[b].chezmoi_managed then
          return b
        end
      end
    end
  end

  local function collapse_pair_windows()
    if applying or closing_pair then
      return
    end
    local cur_buf = vim.api.nvim_get_current_buf()
    if vim.b[cur_buf].chezmoi_managed or vim.b[cur_buf].chezmoi_is_source then
      return
    end
    applying = true
    hide_source_info()
    hide_dest_warn()
    local cur_win = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_is_valid(cur_win) then
      vim.wo[cur_win].winfixheight = false
    end
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if win ~= cur_win and is_editor_win(win) then
        local b = vim.api.nvim_win_get_buf(win)
        if vim.b[b].chezmoi_is_source or vim.b[b].chezmoi_managed then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
    end
    applying = false
  end

  local function restore_after_close()
    if vim.v.exiting ~= vim.NIL then
      return
    end
    pcall(function()
      local buf = vim.api.nvim_get_current_buf()
      local dest_buf = pair_for(buf)
      if dest_buf then
        layout_pair(dest_buf, { focus_source = true })
      else
        collapse_pair_windows()
      end
      sync_chezmoi_warn()
    end)
  end

  ---@param force boolean
  local function close_pair(force)
    if closing_pair then
      return
    end
    local dest_buf, source_buf = pair_for(vim.api.nvim_get_current_buf())
    if not dest_buf then
      return
    end
    if not force and source_buf and vim.api.nvim_buf_is_valid(source_buf) and vim.bo[source_buf].modified then
      vim.api.nvim_err_writeln("No write since last change for chezmoi source (add ! to override)")
      return
    end

    closing_pair = true
    hide_source_info()
    hide_dest_warn()

    local exclude = { [dest_buf] = true }
    if source_buf then
      exclude[source_buf] = true
    end
    local other = next_listed_except(exclude)

    local cur = vim.api.nvim_get_current_win()
    local pair_wins = {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if is_editor_win(win) then
        local b = vim.api.nvim_win_get_buf(win)
        if b == dest_buf or b == source_buf then
          pair_wins[#pair_wins + 1] = win
        end
      end
    end

    if other then
      if vim.api.nvim_win_is_valid(cur) then
        vim.wo[cur].winfixheight = false
        pcall(vim.api.nvim_win_set_buf, cur, other)
      end
      for _, win in ipairs(pair_wins) do
        if win ~= cur and vim.api.nvim_win_is_valid(win) then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
      if vim.api.nvim_buf_is_valid(dest_buf) then
        pcall(vim.api.nvim_buf_delete, dest_buf, { force = true })
      end
      if source_buf and vim.api.nvim_buf_is_valid(source_buf) then
        pcall(vim.api.nvim_buf_delete, source_buf, { force = force })
      end
      vim.schedule(function()
        closing_pair = false
        restore_after_close()
      end)
    else
      if vim.api.nvim_win_is_valid(cur) then
        vim.wo[cur].winfixheight = false
      end
      for _, win in ipairs(pair_wins) do
        if win ~= cur and vim.api.nvim_win_is_valid(win) then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
      closing_pair = false
      vim.api.nvim_cmd({ cmd = "quit", bang = force }, {})
    end
  end

  ---@param force boolean
  local function smart_quit(force)
    local buf = vim.api.nvim_get_current_buf()
    if vim.bo[buf].buftype ~= "" then
      vim.api.nvim_cmd({ cmd = "quit", bang = force }, {})
      return
    end
    if pair_for(buf) then
      close_pair(force)
      return
    end
    if not force and vim.bo[buf].modified then
      vim.api.nvim_err_writeln("No write since last change (add ! to override)")
      return
    end
    local other = next_listed_except({ [buf] = true })
    if other then
      if Snacks and Snacks.bufdelete then
        pcall(Snacks.bufdelete, { buf = buf, force = force })
      else
        pcall(vim.api.nvim_buf_delete, buf, { force = force })
      end
      vim.schedule(restore_after_close)
    else
      vim.api.nvim_cmd({ cmd = "quit", bang = force }, {})
    end
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

    local dest_buf = pair_for(origin_buf)
    if dest_buf then
      layout_pair(dest_buf, { focus_source = true })
    end

    sync_chezmoi_warn()
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
      if closing_pair or applying then
        return
      end
      if event.event == "WinEnter" then
        sync_chezmoi_warn()
        return
      end
      if not vim.api.nvim_buf_is_valid(event.buf) then
        return
      end
      local dest_buf = pair_for(event.buf)
      if dest_buf then
        layout_pair(dest_buf, { focus_source = vim.b[event.buf].chezmoi_is_source == true })
        sync_chezmoi_warn()
      elseif vim.bo[event.buf].buftype == "" then
        collapse_pair_windows()
        sync_chezmoi_warn()
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    callback = function(event)
      if closing_pair or applying then
        return
      end
      local dest_buf, source_buf = pair_for(event.buf)
      if not dest_buf then
        return
      end
      local other = event.buf == dest_buf and source_buf or dest_buf
      vim.schedule(function()
        closing_pair = true
        if other and vim.api.nvim_buf_is_valid(other) then
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == other then
              pcall(vim.api.nvim_win_close, win, true)
            end
          end
          pcall(vim.api.nvim_buf_delete, other, { force = true })
        end
        hide_source_info()
        closing_pair = false
        sync_chezmoi_warn()
      end)
    end,
  })

  vim.api.nvim_create_user_command("ChezmoiSmartQuit", function(opts)
    smart_quit(opts.bang)
  end, { bang = true, desc = "Quit current buffer or chezmoi dest/source pair" })

  vim.cmd([[
    function! ChezmoiPairQuitAbbr(cmd) abort
      if getcmdtype() !=# ':'
        return a:cmd
      endif
      if &buftype !=# ''
        return a:cmd
      endif
      let l:line = getcmdline()
      if l:line ==# a:cmd
        return 'ChezmoiSmartQuit'
      endif
      if l:line ==# a:cmd . '!'
        return 'ChezmoiSmartQuit!'
      endif
      return a:cmd
    endfunction
    cnoreabbrev <expr> q ChezmoiPairQuitAbbr('q')
    cnoreabbrev <expr> quit ChezmoiPairQuitAbbr('quit')
  ]])

  vim.api.nvim_create_autocmd("BufReadPost", {
    group = group,
    callback = function(event)
      consider_buf(event.buf)
    end,
  })

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
