-- Turns the parsed diff model into display lines plus the metadata needed to
-- map every buffer line back to a (file, side, line-number) tuple.
local M = {}

-- "%4s %4s %s " -> 4 + 1 + 4 + 1 + 1 + 1 = 12 columns before the code text.
local GUTTER = 12

local function gutter(old, new, sign)
  local o = old and string.format("%4d", old) or "    "
  local n = new and string.format("%4d", new) or "    "
  return string.format("%s %s %s ", o, n, sign)
end

-- Returns { lines, map, marks, file_lines, gutter }.
--   map[i]   = metadata for display line i (1-based)
--   marks    = { { line, line_hl?, gutter_hl? } } highlight instructions
--   file_lines[path] = display line of that file's header
function M.build(files)
  local lines, map, marks, file_lines, hunk_rows = {}, {}, {}, {}, {}

  local function push(text, meta, hl)
    table.insert(lines, text)
    local idx = #lines
    map[idx] = meta
    if hl then
      hl.line = idx
      table.insert(marks, hl)
    end
    return idx
  end

  for _, f in ipairs(files) do
    if #lines > 0 then
      push("", { kind = "blank" })
    end

    local stat = string.format("  +%d -%d", f.add or 0, f.del or 0)
    local status = (f.status and f.status ~= "modified") and ("  [" .. f.status .. "]") or ""
    file_lines[f.path] = push(
      "▌ " .. (f.path or "?") .. stat .. status,
      { kind = "file_header", file = f.path },
      { line_hl = "TackFileHeader" }
    )

    if f.binary then
      push("      (binary file)", { kind = "info", file = f.path })
    end

    for hi, h in ipairs(f.hunks) do
      table.insert(hunk_rows, push(h.header, { kind = "hunk_header", file = f.path, hunk = hi }, { line_hl = "TackHunkHeader" }))
      for _, l in ipairs(h.lines) do
        local sign = (l.kind == "add" and "+") or (l.kind == "del" and "-") or " "
        local hl = { gutter_hl = "TackLineNr" }
        if l.kind == "add" then
          hl.line_hl = "TackAdd"
        elseif l.kind == "del" then
          hl.line_hl = "TackDelete"
        end
        push(
          gutter(l.old_line, l.new_line, sign) .. l.text,
          { kind = l.kind, file = f.path, old_line = l.old_line, new_line = l.new_line },
          hl
        )
      end
    end
  end

  if #lines == 0 then
    push("No changes.", { kind = "info" })
  end

  return { lines = lines, map = map, marks = marks, file_lines = file_lines, hunk_rows = hunk_rows, gutter = GUTTER }
end

-- "%5s %s " => 5 (number) + 1 + 1 (sign) + 1 = 8 columns before the code text.
local SPLIT_GUTTER = 8

-- Builds two aligned sides (old | new) for a side-by-side view. Removed lines
-- sit on the left, added lines on the right, paired row-for-row within each
-- change block, with blank filler rows padding the shorter side so both buffers
-- stay line-aligned (required for scrollbind).
function M.build_split(files)
  local L = { lines = {}, map = {}, marks = {} }
  local R = { lines = {}, map = {}, marks = {} }
  local file_lines, hunk_rows = {}, {}

  local function row(ltext, rtext)
    table.insert(L.lines, ltext or "")
    table.insert(R.lines, rtext or "")
    return #L.lines
  end
  local function lmark(i, o) o.line = i; table.insert(L.marks, o) end
  local function rmark(i, o) o.line = i; table.insert(R.marks, o) end
  local function sign_of(kind)
    return (kind == "add" and "+") or (kind == "del" and "-") or " "
  end
  local function cell(num, kind, text)
    return string.format("%5s %s %s", num and tostring(num) or "", sign_of(kind), text)
  end

  for _, f in ipairs(files) do
    if #L.lines > 0 then
      row("", "")
    end

    local stat = string.format("  +%d -%d", f.add or 0, f.del or 0)
    local status = (f.status and f.status ~= "modified") and ("  [" .. f.status .. "]") or ""
    local hr = row("▌ " .. (f.path or "?") .. stat .. status, "")
    file_lines[f.path] = hr
    lmark(hr, { line_hl = "TackFileHeader" })
    rmark(hr, { line_hl = "TackFileHeader" })

    if f.binary then
      row("      (binary file)", "")
    end

    for _, h in ipairs(f.hunks) do
      local hh = row(h.header, "")
      table.insert(hunk_rows, hh)
      lmark(hh, { line_hl = "TackHunkHeader" })
      rmark(hh, { line_hl = "TackHunkHeader" })

      local dels, adds = {}, {}
      local function flush()
        for i = 1, math.max(#dels, #adds) do
          local d, a = dels[i], adds[i]
          local ri = row(
            d and cell(d.old_line, "del", d.text) or "",
            a and cell(a.new_line, "add", a.text) or ""
          )
          if d then
            L.map[ri] = { file = f.path, side = "old", old_line = d.old_line, kind = "del" }
            lmark(ri, { line_hl = "TackDelete", gutter_hl = "TackLineNr" })
          else
            lmark(ri, { line_hl = "TackFiller" })
          end
          if a then
            R.map[ri] = { file = f.path, side = "new", new_line = a.new_line, kind = "add" }
            rmark(ri, { line_hl = "TackAdd", gutter_hl = "TackLineNr" })
          else
            rmark(ri, { line_hl = "TackFiller" })
          end
        end
        dels, adds = {}, {}
      end

      for _, l in ipairs(h.lines) do
        if l.kind == "context" then
          flush()
          local ri = row(cell(l.old_line, "context", l.text), cell(l.new_line, "context", l.text))
          L.map[ri] = { file = f.path, side = "old", old_line = l.old_line, kind = "context" }
          R.map[ri] = { file = f.path, side = "new", new_line = l.new_line, kind = "context" }
          lmark(ri, { gutter_hl = "TackLineNr" })
          rmark(ri, { gutter_hl = "TackLineNr" })
        elseif l.kind == "del" then
          if #adds > 0 then flush() end
          table.insert(dels, l)
        elseif l.kind == "add" then
          table.insert(adds, l)
        end
      end
      flush()
    end
  end

  if #L.lines == 0 then
    row("No changes.", "")
  end

  return { left = L, right = R, file_lines = file_lines, hunk_rows = hunk_rows, gutter = SPLIT_GUTTER }
end

return M
