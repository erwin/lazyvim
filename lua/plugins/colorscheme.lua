return {
  {
    "miikanissi/modus-themes.nvim",
    lazy = false,
    priority = 1000,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      -- Modus provides a unified canvas name that responds to :set background=light/dark
      colorscheme = "modus",
    },
  },
}
