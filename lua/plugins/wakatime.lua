return {
  "wakatime/vim-wakatime",
  lazy = false,
  -- Servers / install_gui=false do not export WAKATIME_API_KEY.
  cond = function()
    local key = vim.env.WAKATIME_API_KEY
    return type(key) == "string" and key ~= ""
  end,
}
