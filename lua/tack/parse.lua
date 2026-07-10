-- Parses a unified diff blob into a structured model:
--   files = {
--     { path, old_path, new_path, status, binary, add, del,
--       hunks = {
--         { header, context, old_start, new_start,
--           lines = { { kind = "add"|"del"|"context", text, old_line, new_line } } } } } }
local M = {}

-- Decodes git's C-style quoting. `core.quotepath=false` stops octal-escaping of
-- non-ASCII bytes, but git still wraps any path containing a quote, backslash,
-- tab, newline, etc. in double quotes with escapes -- so we must undo that.
local function git_unquote(s)
  if s:sub(1, 1) ~= '"' then
    return s
  end
  local body = s:sub(2, -2)
  local out, i, n = {}, 1, #body
  local esc = { a = "\a", b = "\b", t = "\t", n = "\n", v = "\v", f = "\f", r = "\r", ['"'] = '"', ["\\"] = "\\" }
  while i <= n do
    local ch = body:sub(i, i)
    if ch == "\\" then
      local oct = body:match("^%d%d%d", i + 1)
      if oct then
        table.insert(out, string.char(tonumber(oct, 8)))
        i = i + 4
      else
        local nx = body:sub(i + 1, i + 1)
        table.insert(out, esc[nx] or nx)
        i = i + 2
      end
    else
      table.insert(out, ch)
      i = i + 1
    end
  end
  return table.concat(out)
end

local function strip_prefix(p)
  -- Drop a trailing tab + timestamp some git versions append (only matches a
  -- real tab byte, so an in-name "\t" inside quotes is left for git_unquote).
  p = p:gsub("\t.*$", "")
  p = git_unquote(p)
  if p == "/dev/null" then
    return nil
  end
  return (p:gsub("^[ab]/", ""))
end

function M.parse(text)
  local files = {}
  local cur, hunk

  for line in (text .. "\n"):gmatch("(.-)\n") do
    local c = line:sub(1, 1)

    if line:match("^diff %-%-git ") then
      cur = { hunks = {}, status = "modified", binary = false }
      table.insert(files, cur)
      hunk = nil
      local a, b = line:match("^diff %-%-git a/(.-) b/(.+)$")
      if a then cur.old_path = a end
      if b then cur.new_path = b end
    elseif cur and line:match("^new file mode") then
      cur.status = "added"
    elseif cur and line:match("^deleted file mode") then
      cur.status = "deleted"
    elseif cur and line:match("^rename from ") then
      cur.status = "renamed"
      cur.old_path = git_unquote(line:sub(#"rename from " + 1))
    elseif cur and line:match("^rename to ") then
      cur.status = "renamed"
      cur.new_path = git_unquote(line:sub(#"rename to " + 1))
    elseif cur and line:match("^Binary files ") then
      cur.binary = true
    -- `---`/`+++` headers only appear before the first `@@` of a file (hunk is
    -- still nil there). Gating on `not hunk` stops a deleted "-- ..." or added
    -- "++ ..." body line from being mistaken for a header.
    elseif cur and not hunk and line:match("^%-%-%- ") then
      cur.old_path = strip_prefix(line:sub(5)) or cur.old_path
    elseif cur and not hunk and line:match("^%+%+%+ ") then
      cur.new_path = strip_prefix(line:sub(5)) or cur.new_path
    elseif cur and c == "@" and line:match("^@@ ") then
      local os_, oc, ns, nc, ctx = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@(.*)$")
      if os_ then
        hunk = {
          old_start = tonumber(os_),
          old_count = tonumber(oc) or 1,
          new_start = tonumber(ns),
          new_count = tonumber(nc) or 1,
          context = (ctx or ""):gsub("^%s+", ""),
          header = line,
          lines = {},
          -- running counters used while consuming body lines
          _old = tonumber(os_),
          _new = tonumber(ns),
        }
        table.insert(cur.hunks, hunk)
      end
    elseif cur and hunk then
      if c == "+" then
        table.insert(hunk.lines, { kind = "add", text = line:sub(2), new_line = hunk._new })
        hunk._new = hunk._new + 1
      elseif c == "-" then
        table.insert(hunk.lines, { kind = "del", text = line:sub(2), old_line = hunk._old })
        hunk._old = hunk._old + 1
      elseif c == " " then
        table.insert(hunk.lines, {
          kind = "context", text = line:sub(2),
          old_line = hunk._old, new_line = hunk._new,
        })
        hunk._old = hunk._old + 1
        hunk._new = hunk._new + 1
      end
      -- "\ No newline at end of file" and anything else inside a hunk is ignored.
    end
  end

  for _, f in ipairs(files) do
    f.path = f.new_path or f.old_path
    local add, del = 0, 0
    for _, h in ipairs(f.hunks) do
      h._old, h._new = nil, nil
      for _, l in ipairs(h.lines) do
        if l.kind == "add" then
          add = add + 1
        elseif l.kind == "del" then
          del = del + 1
        end
      end
    end
    f.add, f.del = add, del
  end

  return files
end

return M
