-- 1. Helper function to query the system's current color scheme
local function get_system_theme()
  local handle = io.popen("gsettings get org.gnome.desktop.interface color-scheme")
  if not handle then
    return "dark"
  end

  local result = handle:read("*a")
  handle:close()

  result = result:gsub("['%\n]", "")

  if result == "prefer-light" or result == "default" then
    return "light"
  else
    return "dark"
  end
end

-- 2. Determine the theme mode on startup
local system_mode = get_system_theme()

return {
  -- Configure the modus-themes plugin options
  {
    "miikanissi/modus-themes.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("modus-themes").setup({
        -- The modern configuration uses a 'variants' table to specify
        -- preferences for individual themes
        variants = {
          modus_operandi = "default", -- options: default, tinted, deutan, tritan
          modus_vivendi = "default",
        },
      })
    end,
  },

  -- Configure LazyVim to load the correct variant
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = system_mode == "light" and "modus_operandi" or "modus_vivendi",
    },
  },
}
