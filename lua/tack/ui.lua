-- Owns the review buffers/windows (unified or side-by-side), highlights,
-- comment markers, navigation, and the quickfix list.
local config = require("tack.config")
local git = require("tack.git")
local parse = require("tack.parse")
local render = require("tack.render")
local store = require("tack.store")
local syntax = require("tack.syntax")

local M = {}
local uv = vim.uv or vim.loop

local ns = vim.api.nvim_create_namespace("tack_render")
local cns = vim.api.nvim_create_namespace("tack_comments")
local sns = vim.api.nvim_create_namespace("tack_syntax")

-- M.state.bufs maps each review buffer to its per-buffer data:
--   { map, rev, gutter, hunk_lines, comment_lines }
-- map[row] = { file, side = "old"|"new", old_line?/new_line?, kind }
-- rev["file|side|line"] = row  (reverse index for placing comment markers)
M.state = {
  view = nil,          -- "split" | "unified" (resolved at open time)
  base = nil,          -- per-session diff base (nil => config default)
  model = nil,         -- parsed files
  bufs = {},           -- bufnr -> per-buffer data
  unified = nil,       -- bufnr (unified view)
  left = nil,          -- bufnr (split, old side)
  right = nil,         -- bufnr (split, new side)
}

local function rev_key(file, side, line)
  return string.format("%s|%s|%d", file or "", side or "", line or -1)
end

local function buf_valid(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

function M.define_highlights()
  local cfg = config.get()
  local function link(name, target)
    vim.api.nvim_set_hl(0, name, { link = target, default = true })
  end
  link("TackFileHeader", "Title")
  link("TackHunkHeader", "Function")
  link("TackLineNr", "LineNr")
  link("TackFiller", "Folded")
  link("TackCommentSign", cfg.signs.comment_hl or "DiagnosticInfo")
  link("TackCommentText", cfg.virt.hl or "Comment")

  -- Diff rows need a BACKGROUND-ONLY highlight so code keeps its treesitter /
  -- normal foreground. Many themes give DiffAdd/DiffDelete only a green/red
  -- *foreground* and no background, so we can't just reuse the group: we'd lose
  -- the row tint and force every char one color. Instead: use the theme's diff
  -- background if it has one, otherwise synthesize a subtle one by blending the
  -- diff foreground into the Normal background. Re-derived on every ColorScheme.
  local function channels(n)
    return math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256
  end
  local function blend(top, bottom, alpha)
    local r1, g1, b1 = channels(top)
    local r2, g2, b2 = channels(bottom)
    local r = math.floor(r1 * alpha + r2 * (1 - alpha) + 0.5)
    local g = math.floor(g1 * alpha + g2 * (1 - alpha) + 0.5)
    local b = math.floor(b1 * alpha + b2 * (1 - alpha) + 0.5)
    return r * 65536 + g * 256 + b
  end
  local nbg = (vim.api.nvim_get_hl(0, { name = "Normal", link = false }) or {}).bg or 0x000000
  local function row_bg(source, fallback)
    local hl = vim.api.nvim_get_hl(0, { name = source, link = false }) or {}
    if hl.bg then
      return hl.bg
    end
    if hl.fg then
      return blend(hl.fg, nbg, 0.18)
    end
    return fallback
  end
  vim.api.nvim_set_hl(0, "TackAdd", { bg = row_bg("DiffAdd", 0x1b2a1b) })
  vim.api.nvim_set_hl(0, "TackDelete", { bg = row_bg("DiffDelete", 0x2a1b1b) })
end

local function setup_buf_options(buf, name)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "tack"
  pcall(vim.api.nvim_buf_set_name, buf, name)
end

local function setup_win_options(win)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].wrap = false
  vim.wo[win].signcolumn = "yes"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].cursorline = true
end

-- Applies treesitter token colors (foreground) over the diff backgrounds by
-- parsing each contiguous run of real source lines for its language.
local function apply_syntax(buf)
  if config.get().syntax == false then
    return
  end
  local bd = M.state.bufs[buf]
  if not bd then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local gutter = bd.gutter or 0

  vim.api.nvim_buf_clear_namespace(buf, sns, 0, -1)

  -- Ordered list of real code rows: { row, file, lineno, code }.
  local rows = {}
  for row = 1, #lines do
    local meta = bd.map[row]
    if meta and (meta.kind == "add" or meta.kind == "del" or meta.kind == "context") then
      rows[#rows + 1] = {
        row = row,
        file = meta.file,
        lineno = meta.new_line or meta.old_line,
        code = lines[row]:sub(gutter + 1),
      }
    end
  end

  -- Group into runs of the same file with consecutive source line numbers, so
  -- each run is a contiguous block treesitter can parse accurately.
  local i = 1
  while i <= #rows do
    local first = i
    local file = rows[i].file
    while i + 1 <= #rows
      and rows[i + 1].file == file
      and rows[i + 1].lineno == rows[i].lineno + 1 do
      i = i + 1
    end

    local lang = syntax.lang_for(file)
    if lang then
      local texts = {}
      for k = first, i do
        texts[#texts + 1] = rows[k].code
      end
      local spans = syntax.highlights(table.concat(texts, "\n"), lang)
      if spans then
        for k = first, i do
          local s = spans[k - first + 1]
          if s then
            local code = rows[k].code
            for _, sp in ipairs(s) do
              local c0, c1 = sp[1], sp[2]
              if c1 < 0 or c1 > #code then c1 = #code end
              if c1 > c0 then
                pcall(vim.api.nvim_buf_set_extmark, buf, sns, rows[k].row - 1, gutter + c0, {
                  end_col = gutter + c1,
                  hl_group = sp[3],
                  priority = 150,
                })
              end
            end
          end
        end
      end
    end
    i = i + 1
  end
end

-- Repaints one buffer from a {lines, marks, map, hunk_rows, gutter} bundle and
-- rebuilds its reverse index.
local function paint(buf, data)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, data.lines)
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, mk in ipairs(data.marks) do
    if mk.line_hl then
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, mk.line - 1, 0, { line_hl_group = mk.line_hl })
    end
    if mk.gutter_hl then
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, mk.line - 1, 0, {
        end_col = math.min(data.gutter, #data.lines[mk.line]),
        hl_group = mk.gutter_hl,
      })
    end
  end

  local rev = {}
  for i, meta in pairs(data.map) do
    if meta.new_line then rev[rev_key(meta.file, "new", meta.new_line)] = i end
    if meta.old_line then rev[rev_key(meta.file, "old", meta.old_line)] = i end
  end

  M.state.bufs[buf] = {
    map = data.map,
    rev = rev,
    gutter = data.gutter,
    hunk_lines = data.hunk_rows or {},
    comment_lines = {},
  }

  apply_syntax(buf)
end

local function get_files()
  local cfg = config.get()
  local eff = vim.tbl_extend("force", cfg, { base = M.state.base or cfg.base })
  local files = parse.parse(git.diff(eff, uv.cwd()))
  M.state.model = files
  return files
end

-- Returns which review buffer a comment of `side` belongs to.
local function buf_for_side(side)
  if M.state.view == "split" then
    return (side == "new") and M.state.right or M.state.left
  end
  return M.state.unified
end

-- Paints comment signs + end-of-line virtual text across all review buffers.
function M.draw_comments()
  local cfg = config.get()
  for buf, bd in pairs(M.state.bufs) do
    if buf_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, cns, 0, -1)
    end
    bd.comment_lines = {}
  end

  for _, c in ipairs(store.read().comments) do
    local side = c.side or (c.newLine and "new") or "old"
    local line = (side == "new") and (c.newLine or c.lineStart) or (c.oldLine or c.lineStart)
    local buf = buf_for_side(side)
    local bd = buf and M.state.bufs[buf]
    if bd and bd.rev and buf_valid(buf) then
      local disp = bd.rev[rev_key(c.filePath, side, line)]
      if disp then
        local label = (c.status == "resolved") and ("✓ " .. (c.summary or ""))
          or (cfg.virt.prefix .. (c.summary or ""))
        pcall(vim.api.nvim_buf_set_extmark, buf, cns, disp - 1, 0, {
          sign_text = cfg.signs.comment,
          sign_hl_group = "TackCommentSign",
          virt_text = { { label, "TackCommentText" } },
          virt_text_pos = "eol",
        })
        table.insert(bd.comment_lines, disp)
      end
    end
  end

  for _, bd in pairs(M.state.bufs) do
    table.sort(bd.comment_lines)
  end
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

local function ensure_unified_buf()
  if buf_valid(M.state.unified) then
    return M.state.unified
  end
  local buf = vim.api.nvim_create_buf(false, true)
  setup_buf_options(buf, "tack://review")
  M.state.unified = buf
  M.setup_keymaps(buf)
  return buf
end

local function ensure_split_bufs()
  if not buf_valid(M.state.left) then
    local b = vim.api.nvim_create_buf(false, true)
    setup_buf_options(b, "tack://old")
    M.state.left = b
    M.setup_keymaps(b)
  end
  if not buf_valid(M.state.right) then
    local b = vim.api.nvim_create_buf(false, true)
    setup_buf_options(b, "tack://new")
    M.state.right = b
    M.setup_keymaps(b)
  end
  return M.state.left, M.state.right
end

function M.render()
  if M.state.view == "split" then
    local left, right = ensure_split_bufs()
    local files = get_files()
    local built = render.build_split(files)
    paint(left, { lines = built.left.lines, marks = built.left.marks, map = built.left.map,
      hunk_rows = built.hunk_rows, gutter = built.gutter })
    paint(right, { lines = built.right.lines, marks = built.right.marks, map = built.right.map,
      hunk_rows = built.hunk_rows, gutter = built.gutter })
  else
    local buf = ensure_unified_buf()
    local files = get_files()
    local built = render.build(files)
    paint(buf, { lines = built.lines, marks = built.marks, map = built.map,
      hunk_rows = built.hunk_rows, gutter = built.gutter })
  end
  M.draw_comments()
end

-- ---------------------------------------------------------------------------
-- Windows
-- ---------------------------------------------------------------------------

local function show_unified()
  local cfg = config.get()
  local buf = M.state.unified
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    vim.api.nvim_set_current_win(win)
    return
  end
  if cfg.layout == "tab" then
    vim.cmd("tab sbuffer " .. buf)
  elseif cfg.layout == "vsplit" then
    vim.cmd("vertical sbuffer " .. buf)
  elseif cfg.layout == "split" then
    vim.cmd("sbuffer " .. buf)
  else
    vim.cmd("buffer " .. buf)
  end
  setup_win_options(vim.api.nvim_get_current_win())
end

local function show_split()
  local cfg = config.get()
  local left, right = M.state.left, M.state.right
  if vim.fn.bufwinid(left) ~= -1 then
    vim.api.nvim_set_current_win(vim.fn.bufwinid(left))
    return
  end
  if cfg.layout == "tab" then
    vim.cmd("tabnew")
  end
  vim.cmd("buffer " .. left)
  local w1 = vim.api.nvim_get_current_win()
  vim.cmd("vertical rightbelow sbuffer " .. right)
  local w2 = vim.api.nvim_get_current_win()
  for _, w in ipairs({ w1, w2 }) do
    setup_win_options(w)
    vim.wo[w].scrollbind = true
    vim.wo[w].cursorbind = true
  end
  -- Land on the new side, where most comments are made.
  vim.api.nvim_set_current_win(w2)
  pcall(vim.cmd, "syncbind")
end

function M.open(base)
  M.state.base = base
  M.state.view = config.get().view or "split"
  M.render()
  if M.state.view == "split" then
    show_split()
  else
    show_unified()
  end
end

function M.reload()
  if M.state.view == nil then
    return M.open()
  end
  local saved = {}
  for buf in pairs(M.state.bufs) do
    local w = buf_valid(buf) and vim.fn.bufwinid(buf) or -1
    if w ~= -1 then
      saved[w] = vim.api.nvim_win_call(w, vim.fn.winsaveview)
    end
  end
  M.render()
  for w, view in pairs(saved) do
    if vim.api.nvim_win_is_valid(w) then
      vim.api.nvim_win_call(w, function() vim.fn.winrestview(view) end)
    end
  end
  vim.notify("tack: reloaded", vim.log.levels.INFO)
end

function M.close()
  local closed = false
  for buf in pairs(M.state.bufs) do
    local w = buf_valid(buf) and vim.fn.bufwinid(buf) or -1
    if w ~= -1 and pcall(vim.api.nvim_win_close, w, true) then
      closed = true
    end
  end
  if not closed then
    pcall(vim.cmd, "buffer #")
  end
end

-- ---------------------------------------------------------------------------
-- Navigation / lists (operate on the current window's buffer)
-- ---------------------------------------------------------------------------

local function cur_bd()
  return M.state.bufs[vim.api.nvim_get_current_buf()]
end

local function jump(targets, dir)
  if not targets or #targets == 0 then
    return
  end
  local cur = vim.api.nvim_win_get_cursor(0)[1]
  local dest
  if dir > 0 then
    for _, l in ipairs(targets) do
      if l > cur then dest = l break end
    end
    dest = dest or targets[1]
  else
    for i = #targets, 1, -1 do
      if targets[i] < cur then dest = targets[i] break end
    end
    dest = dest or targets[#targets]
  end
  vim.api.nvim_win_set_cursor(0, { dest, 0 })
end

function M.next_hunk() local bd = cur_bd(); if bd then jump(bd.hunk_lines, 1) end end
function M.prev_hunk() local bd = cur_bd(); if bd then jump(bd.hunk_lines, -1) end end
function M.next_comment() local bd = cur_bd(); if bd then jump(bd.comment_lines, 1) end end
function M.prev_comment() local bd = cur_bd(); if bd then jump(bd.comment_lines, -1) end end

function M.list()
  local root = git.root(uv.cwd()) or uv.cwd()
  local items = {}
  for _, c in ipairs(store.read().comments) do
    table.insert(items, {
      filename = root .. "/" .. c.filePath,
      lnum = c.newLine or c.oldLine or c.lineStart or 1,
      text = string.format("[%s%s] %s",
        c.author or "?",
        c.status == "resolved" and "/resolved" or "",
        c.summary or ""),
    })
  end
  vim.fn.setqflist({}, " ", { title = "Hunk comments", items = items })
  if #items == 0 then
    vim.notify("tack: no comments yet", vim.log.levels.INFO)
  else
    vim.cmd("copen")
  end
end

function M.remove_under_cursor()
  local row = vim.api.nvim_win_get_cursor(0)[1]

  -- Collect the (file, side, line) anchors at this display row across all review
  -- panes, so removal works from either side in split view and the panes stay in
  -- sync (rows are aligned, scrollbound).
  local anchors = {}
  for _, bd in pairs(M.state.bufs) do
    local meta = bd.map[row]
    if meta then
      if meta.new_line then
        anchors[#anchors + 1] = { file = meta.file, side = "new", line = meta.new_line }
      end
      if meta.old_line then
        anchors[#anchors + 1] = { file = meta.file, side = "old", line = meta.old_line }
      end
    end
  end
  if #anchors == 0 then
    vim.notify("tack: no comment on this line", vim.log.levels.WARN)
    return
  end

  for _, c in ipairs(store.read().comments) do
    local side = c.side or (c.newLine and "new") or "old"
    local lo = c.lineStart or c.newLine or c.oldLine
    local hi = c.lineEnd or lo
    for _, a in ipairs(anchors) do
      if a.file == c.filePath and a.side == side and lo and a.line >= lo and a.line <= hi then
        store.remove(c.id)
        M.draw_comments()
        vim.notify("tack: removed comment", vim.log.levels.INFO)
        return
      end
    end
  end
  vim.notify("tack: no comment on this line", vim.log.levels.WARN)
end

function M.setup_keymaps(buf)
  local km = config.get().keymaps
  local function map(mode, lhs, rhs)
    if lhs and lhs ~= "" then
      vim.keymap.set(mode, lhs, rhs, { buffer = buf, silent = true, nowait = true })
    end
  end
  map("x", km.comment, ":<C-u>lua require('tack.comment').add_visual()<CR>")
  map("n", km.comment, "<Cmd>lua require('tack.comment').add_line()<CR>")
  map("n", km.remove, M.remove_under_cursor)
  map("n", km.list, M.list)
  map("n", km.reload, M.reload)
  map("n", km.next_hunk, M.next_hunk)
  map("n", km.prev_hunk, M.prev_hunk)
  map("n", km.next_comment, M.next_comment)
  map("n", km.prev_comment, M.prev_comment)
  map("n", km.quit, M.close)
end

return M
