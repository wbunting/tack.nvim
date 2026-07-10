-- Public API + user commands for tack.nvim.
local config = require("tack.config")

local M = {}

function M.review(base)
  require("tack.ui").open(base)
end

function M.reload()
  require("tack.ui").reload()
end

function M.list()
  require("tack.ui").list()
end

function M.comment(l1, l2)
  require("tack.comment").add(l1, l2)
end

-- Remove the comment under the cursor, in a diff review buffer or a file buffer.
function M.remove()
  local ui = require("tack.ui")
  if ui.state.bufs[vim.api.nvim_get_current_buf()] then
    ui.remove_under_cursor()
  elseif require("tack.annotate").remove_at_cursor() then
    require("tack.annotate").refresh()
    vim.notify("tack: removed comment", vim.log.levels.INFO)
  else
    vim.notify("tack: no comment on this line", vim.log.levels.WARN)
  end
end

function M.clear(file)
  require("tack.store").clear(file)
  pcall(function()
    require("tack.ui").draw_comments()
  end)
  pcall(function()
    require("tack.annotate").refresh()
  end)
end

function M._create_commands()
  vim.api.nvim_create_user_command("TackReview", function(o)
    M.review(o.args ~= "" and o.args or nil)
  end, { nargs = "?", desc = "Open the hunk diff review (optional base ref/range)" })

  vim.api.nvim_create_user_command("TackReload", function()
    M.reload()
  end, { desc = "Re-run the diff and repaint the review" })

  vim.api.nvim_create_user_command("TackComments", function()
    M.list()
  end, { desc = "List all review comments in the quickfix window" })

  vim.api.nvim_create_user_command("TackComment", function(o)
    M.comment(o.line1, o.line2)
  end, { range = true, desc = "Comment on the selected/current line(s)" })

  vim.api.nvim_create_user_command("TackClear", function(o)
    M.clear(o.args ~= "" and o.args or nil)
    vim.notify("tack: cleared comments", vim.log.levels.INFO)
  end, { nargs = "?", desc = "Clear all comments (or just those for a file)" })

  vim.api.nvim_create_user_command("TackRemove", function()
    M.remove()
  end, { desc = "Remove the comment under the cursor" })
end

-- Idempotent (augroup is cleared): safe to call from setup() and plugin/hunk.lua.
function M._setup_autocmds()
  local grp = vim.api.nvim_create_augroup("TackNvim", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = grp,
    callback = function()
      require("tack.ui").define_highlights()
    end,
  })
  -- Render comment markers in normal file buffers as they are loaded.
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = grp,
    callback = function(ev)
      require("tack.annotate").draw(ev.buf)
    end,
  })
end

function M.setup(opts)
  config.setup(opts)
  require("tack.ui").define_highlights()
  M._create_commands()
  M._setup_autocmds()
end

return M
