-- Zero-config bootstrap: makes the :Tack* commands and highlights available
-- without an explicit require("tack").setup(). Calling setup() later still works
-- and is the way to override configuration.
if vim.g.loaded_tack_nvim then
  return
end
vim.g.loaded_tack_nvim = true

require("tack.ui").define_highlights()
require("tack")._create_commands()
require("tack")._setup_autocmds()
