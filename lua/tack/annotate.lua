-- Renders review comments inside normal file buffers (not just the diff review),
-- so you can comment on any line of any file to point an agent at it. Uses the
-- same .tack/review.json sidecar as the diff view.
local config = require("tack.config")
local git = require("tack.git")
local store = require("tack.store")

local M = {}
local uv = vim.uv or vim.loop
local ns = vim.api.nvim_create_namespace("tack_file_comments")

-- Repo-relative path for an absolute file name (falls back to the absolute path
-- when the file is outside any git repo). Returns path, root.
function M.relpath(name)
  if not name or name == "" then
    return nil
  end
  name = vim.fn.fnamemodify(name, ":p")
  local root = git.root(vim.fn.fnamemodify(name, ":h"))
  if root and name:sub(1, #root + 1) == root .. "/" then
    return name:sub(#root + 2), root
  end
  return name, root
end

local function is_file_buf(buf)
  return vim.api.nvim_buf_is_valid(buf)
    and vim.bo[buf].buftype == ""
    and vim.api.nvim_buf_get_name(buf) ~= ""
end

local function matches(comment, rel, abs)
  return comment.filePath == rel or comment.filePath == abs
end

-- Draws the new-side comments anchored to this file buffer.
function M.draw(buf)
  if not is_file_buf(buf) then
    return
  end
  local abs = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":p")
  local rel = M.relpath(abs)
  if not rel then
    return
  end
  local cfg = config.get()
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local total = vim.api.nvim_buf_line_count(buf)

  for _, c in ipairs(store.read().comments) do
    local side = c.side or (c.newLine and "new") or "old"
    -- Only new-side comments map onto current file content.
    if side == "new" and matches(c, rel, abs) then
      local line = c.newLine or c.lineStart
      if line and line >= 1 and line <= total then
        local label = (c.status == "resolved") and ("✓ " .. (c.summary or ""))
          or (cfg.virt.prefix .. (c.summary or ""))
        pcall(vim.api.nvim_buf_set_extmark, buf, ns, line - 1, 0, {
          sign_text = cfg.signs.comment,
          sign_hl_group = "TackCommentSign",
          virt_text = { { label, "TackCommentText" } },
          virt_text_pos = "eol",
        })
      end
    end
  end
end

-- Redraws annotations across every loaded file buffer.
function M.refresh()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and is_file_buf(buf) then
      M.draw(buf)
    end
  end
end

-- Removes the comment anchored at the cursor in the current file buffer.
-- Returns true if one was removed.
function M.remove_at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  if not is_file_buf(buf) then
    return false
  end
  local abs = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":p")
  local rel = M.relpath(abs)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  for _, c in ipairs(store.read().comments) do
    local side = c.side or (c.newLine and "new") or "old"
    local lo = c.lineStart or c.newLine or c.oldLine
    local hi = c.lineEnd or lo
    if side == "new" and matches(c, rel, abs) and lo and line >= lo and line <= hi then
      store.remove(c.id)
      return true
    end
  end
  return false
end

return M
