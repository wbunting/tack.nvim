-- Treesitter syntax highlighting for the diff buffers. The review buffers have
-- filetype "hunk" (and a line-number gutter mixed into the text), so Neovim's
-- native highlighter can't color the code. Instead we parse each contiguous run
-- of real source lines with a string parser and return per-line capture spans,
-- which ui.lua applies as foreground extmarks on top of the diff backgrounds.
local M = {}

-- Filetypes whose treesitter language name differs from the filetype and isn't
-- always discoverable via get_lang (e.g. *.tsx -> ft "typescriptreact" -> "tsx").
local ALIASES = {
  typescriptreact = "tsx",
  javascriptreact = "javascript",
  ["javascript.jsx"] = "javascript",
  ["typescript.tsx"] = "tsx",
}

local lang_cache = {}

local function parser_available(lang)
  return lang ~= nil and select(1, pcall(vim.treesitter.get_string_parser, "", lang)) == true
end

-- Maps a file path to a treesitter language whose parser is actually installed,
-- or nil. Tries get_lang(ft), then our alias, then the raw ft, and returns the
-- first candidate that has a loadable parser. Results are cached per filetype.
function M.lang_for(path)
  if not path then
    return nil
  end
  local ft = vim.filetype.match({ filename = path })
  if not ft then
    return nil
  end
  local cached = lang_cache[ft]
  if cached ~= nil then
    return cached or nil
  end

  local seen, candidates = {}, {}
  local function add(l)
    if l and not seen[l] then
      seen[l] = true
      candidates[#candidates + 1] = l
    end
  end
  local ok, lang = pcall(vim.treesitter.language.get_lang, ft)
  if ok then
    add(lang)
  end
  add(ALIASES[ft])
  add(ft)

  local resolved
  for _, l in ipairs(candidates) do
    if parser_available(l) then
      resolved = l
      break
    end
  end
  lang_cache[ft] = resolved or false
  return resolved
end

-- Parses a contiguous source block and returns:
--   spans[i] = { { col0, col1, "@capture" }, ... }   (1-based line i, 0-based cols)
-- col1 == -1 means "to end of line". Returns nil if the language has no parser
-- or highlights query installed (caller falls back to no syntax).
function M.highlights(text, lang)
  if not lang then
    return nil
  end
  local ok, parser = pcall(vim.treesitter.get_string_parser, text, lang)
  if not ok or not parser then
    return nil
  end
  local query = vim.treesitter.query.get(lang, "highlights")
  if not query then
    return nil
  end
  local trees = parser:parse()
  if not trees or not trees[1] then
    return nil
  end
  local root = trees[1]:root()

  local spans = {}
  for id, node in query:iter_captures(root, text, 0, -1) do
    local name = query.captures[id]
    -- Skip internal captures (e.g. "_foo") that aren't meant to be displayed.
    if name:sub(1, 1) ~= "_" then
      local sr, sc, er, ec = node:range()
      local group = "@" .. name
      for r = sr, er do
        local c0 = (r == sr) and sc or 0
        local c1 = (r == er) and ec or -1
        spans[r + 1] = spans[r + 1] or {}
        table.insert(spans[r + 1], { c0, c1, group })
      end
    end
  end
  return spans
end

return M
