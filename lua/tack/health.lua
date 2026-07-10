-- Health checks for tack.nvim. Run with `:checkhealth tack`.
local M = {}

local uv = vim.uv or vim.loop

local function first_line(cmd)
  local out = vim.fn.systemlist(cmd)
  return out and out[1] or nil
end

function M.check()
  local h = vim.health
  h.start("tack.nvim")

  -- Neovim version -----------------------------------------------------------
  if vim.fn.has("nvim-0.10") == 1 then
    h.ok("Neovim " .. tostring(vim.version()))
  else
    h.error("Neovim >= 0.10 required (tack uses vim.system, vim.uv, vim.islist)")
  end

  -- git ----------------------------------------------------------------------
  if vim.fn.executable("git") == 1 then
    h.ok(first_line({ "git", "--version" }) or "git found")
  else
    h.error("`git` not found on PATH — tack builds its diff with git")
  end

  -- Treesitter ---------------------------------------------------------------
  if vim.treesitter and vim.treesitter.get_string_parser then
    h.ok("Treesitter required dependency available")
  else
    h.error("Treesitter required — tack uses vim.treesitter to render syntax-highlighted diffs")
  end

  -- Config -------------------------------------------------------------------
  local cfg = require("tack.config").get()
  h.info(("view = %q, base = %q, layout = %q"):format(cfg.view, cfg.base, cfg.layout))
  if cfg.view ~= "split" and cfg.view ~= "unified" then
    h.warn(("view = %q is not \"split\" or \"unified\""):format(cfg.view))
  end

  -- Sidecar ------------------------------------------------------------------
  local store = require("tack.store")
  local ok, path = pcall(store.path)
  if not ok then
    return
  end
  if uv.fs_stat(path) then
    local comments = store.read().comments or {}
    local open = 0
    for _, c in ipairs(comments) do
      if c.status ~= "resolved" then
        open = open + 1
      end
    end
    h.ok(("sidecar %s — %d comment(s), %d open"):format(path, #comments, open))
  else
    h.info("no sidecar yet (created on your first comment): " .. path)
  end
end

return M
