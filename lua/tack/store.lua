-- Persists review comments to the sidecar JSON file the agent consumes.
local config = require("tack.config")
local git = require("tack.git")

local M = {}
local counter = 0
local uv = vim.uv or vim.loop

-- Minimal pretty JSON encoder. Uses vim.json.encode for scalar escaping and
-- emits stable (sorted) keys so the file diffs cleanly in git.
local function encode(value, indent)
  indent = indent or ""
  local pad = indent .. "  "
  local t = type(value)
  if t == "table" then
    if next(value) == nil then
      return "[]"
    end
    if vim.islist(value) then
      local parts = {}
      for _, v in ipairs(value) do
        table.insert(parts, pad .. encode(v, pad))
      end
      return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
    end
    local keys = {}
    for k in pairs(value) do
      table.insert(keys, k)
    end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
      table.insert(parts, pad .. vim.json.encode(k) .. ": " .. encode(value[k], pad))
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
  elseif t == "string" then
    return vim.json.encode(value)
  elseif t == "number" or t == "boolean" then
    return tostring(value)
  end
  return "null"
end

-- Absolute path of the sidecar file.
function M.path()
  local s = config.get().sidecar
  -- Already absolute? (Unix "/..." or Windows "C:\..." / "C:/...")
  if s:match("^/") or s:match("^%a:[/\\]") then
    return s
  end
  local root = git.root(uv.cwd()) or uv.cwd()
  return root .. "/" .. s
end

function M.read()
  local p = M.path()
  local fd = io.open(p, "r")
  if not fd then
    return { version = 1, comments = {} }
  end
  local content = fd:read("*a")
  fd:close()
  if not content or content == "" then
    return { version = 1, comments = {} }
  end
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then
    -- Don't silently drop a non-empty-but-unparseable file: a later write would
    -- clobber recoverable data. Preserve it as a backup and warn instead.
    local bak = p .. ".corrupt"
    pcall(os.rename, p, bak)
    vim.schedule(function()
      vim.notify("tack: unparseable sidecar, backed up to " .. bak, vim.log.levels.ERROR)
    end)
    return { version = 1, comments = {} }
  end
  data.version = data.version or 1
  data.comments = data.comments or {}
  return data
end

function M.write(data)
  local p = M.path()
  vim.fn.mkdir(vim.fn.fnamemodify(p, ":h"), "p")
  -- Serialize first so an encode error aborts before we touch the file, then
  -- write to a temp file and atomically rename over the target.
  local payload = encode(data) .. "\n"
  local tmp = p .. ".tmp"
  local fd, err = io.open(tmp, "w")
  if not fd then
    error("tack: cannot write " .. tmp .. ": " .. tostring(err))
  end
  fd:write(payload)
  fd:close()
  local ok, rerr = os.rename(tmp, p)
  if not ok then
    os.remove(tmp)
    error("tack: cannot replace " .. p .. ": " .. tostring(rerr))
  end
end

-- A process-stable random salt keeps ids unique even when two nvim sessions
-- create their first comment in the same wall-clock second.
local salt = nil
function M.new_id()
  if not salt then
    local addr = tonumber((tostring({}):match("0x(%x+)")) or "0", 16) or 0
    math.randomseed(os.time() + (addr % 0x7fffffff))
    salt = math.random(0, 0xffff)
  end
  counter = counter + 1
  return string.format("c%d-%x-%d", os.time(), salt, counter)
end

function M.append(comment)
  local data = M.read()
  table.insert(data.comments, comment)
  M.write(data)
  return comment
end

function M.remove(id)
  local data = M.read()
  local kept = {}
  for _, c in ipairs(data.comments) do
    if c.id ~= id then
      table.insert(kept, c)
    end
  end
  data.comments = kept
  M.write(data)
end

function M.clear(file)
  local data = M.read()
  if not file then
    data.comments = {}
  else
    local kept = {}
    for _, c in ipairs(data.comments) do
      if c.filePath ~= file then
        table.insert(kept, c)
      end
    end
    data.comments = kept
  end
  M.write(data)
end

return M
