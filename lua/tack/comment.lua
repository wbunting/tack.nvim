-- Captures a comment from a selection in the review buffer and stores it.
local config = require("tack.config")
local store = require("tack.store")
local ui = require("tack.ui")

local M = {}

-- Collects code/diff line metadata for display rows [l1, l2] in the current
-- review buffer, restricted to the first file the selection touches.
local function rows_in_range(l1, l2)
  local bd = ui.state.bufs[vim.api.nvim_get_current_buf()]
  if not bd then
    return {}, nil
  end
  local rows, file = {}, nil
  for ln = l1, l2 do
    local m = bd.map[ln]
    if m and (m.kind == "add" or m.kind == "del" or m.kind == "context") then
      file = file or m.file
      if m.file == file then
        table.insert(rows, m)
      end
    end
  end
  return rows, file
end

-- Builds an anchor spec for a plain file buffer (the "comment anywhere" path).
local function file_spec(buf, l1, l2)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    vim.notify("tack: not a file buffer", vim.log.levels.WARN)
    return nil
  end
  local rel = require("tack.annotate").relpath(name)
  return { file = rel, side = "new", lstart = math.min(l1, l2), lend = math.max(l1, l2) }
end

-- Resolves a diff-buffer selection into an anchor spec: { file, side, lstart, lend }.
local function spec_for(l1, l2)
  local rows, file = rows_in_range(l1, l2)
  if #rows == 0 then
    vim.notify("tack: select changed or code lines to comment", vim.log.levels.WARN)
    return nil
  end
  -- Prefer the new side (additions/context); fall back to the old side when the
  -- selection is purely deletions.
  local new_nums, old_nums = {}, {}
  for _, m in ipairs(rows) do
    if m.new_line then table.insert(new_nums, m.new_line) end
    if m.old_line then table.insert(old_nums, m.old_line) end
  end
  local side, nums = "new", new_nums
  if #new_nums == 0 then
    side, nums = "old", old_nums
  end
  table.sort(nums)
  return { file = file, side = side, lstart = nums[1], lend = nums[#nums] }
end

local function refresh()
  pcall(function() require("tack.ui").draw_comments() end)
  pcall(function() require("tack.annotate").refresh() end)
end

local function persist(spec, summary, rationale)
  local cfg = config.get()
  local c = {
    id = store.new_id(),
    filePath = spec.file,
    side = spec.side,
    lineStart = spec.lstart,
    lineEnd = spec.lend,
    summary = summary,
    author = cfg.author,
    status = "open",
    createdAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }
  -- Mirror the anchor into hunk.dev's field name so the file is drop-in
  -- compatible with `hunk session comment apply --stdin`.
  if spec.side == "new" then
    c.newLine = spec.lstart
  else
    c.oldLine = spec.lstart
  end
  if rationale and rationale ~= "" then
    c.rationale = rationale
  end
  store.append(c)
  refresh()
  vim.notify(string.format("tack: comment on %s:%d", spec.file, spec.lstart), vim.log.levels.INFO)
end

-- Public, programmatic entry point (also used by the :TackComment range command).
-- Works in both the diff review buffers and ordinary file buffers.
function M.add(l1, l2)
  if l2 < l1 then
    l1, l2 = l2, l1
  end
  local buf = vim.api.nvim_get_current_buf()
  local spec
  if ui.state.bufs[buf] then
    spec = spec_for(l1, l2)
  else
    spec = file_spec(buf, l1, l2)
  end
  if not spec then
    return
  end
  local cfg = config.get()
  vim.ui.input({ prompt = "Comment: " }, function(summary)
    if not summary or summary == "" then
      return
    end
    if cfg.prompt_rationale then
      vim.ui.input({ prompt = "Rationale (optional): " }, function(rationale)
        persist(spec, summary, rationale)
      end)
    else
      persist(spec, summary, nil)
    end
  end)
end

function M.add_visual()
  M.add(vim.fn.line("'<"), vim.fn.line("'>"))
end

function M.add_line()
  local l = vim.fn.line(".")
  M.add(l, l)
end

return M
