-- Git access: produces a single unified-diff blob for the configured base,
-- including synthesized diffs for untracked files (like hunk.dev does).
local M = {}

-- The well-known empty tree object; used when HEAD has no commits yet.
local EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

local function run(args, cwd)
  local res = vim.system(args, { cwd = cwd, text = true }):wait()
  return res.code, res.stdout or "", res.stderr or ""
end

-- Returns the git toplevel for `cwd`, or nil if not in a repo.
function M.root(cwd)
  local code, out = run({ "git", "rev-parse", "--show-toplevel" }, cwd)
  if code ~= 0 then
    return nil
  end
  return (out:gsub("%s+$", ""))
end

local function has_head(cwd)
  local code = run({ "git", "rev-parse", "--verify", "--quiet", "HEAD" }, cwd)
  return code == 0
end

local function ref_exists(name, cwd)
  return run({ "git", "rev-parse", "--verify", "--quiet", name .. "^{commit}" }, cwd) == 0
end

-- Finds the trunk branch: origin's default branch first, then the configured
-- candidate names (preferring their origin/ remotes), then local.
local function detect_trunk(cfg, cwd)
  local candidates = {}
  local code, out = run({ "git", "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD" }, cwd)
  if code == 0 and out ~= "" then
    table.insert(candidates, (out:gsub("%s+$", "")))
  end
  for _, n in ipairs(cfg.trunk or { "main", "master", "trunk" }) do
    table.insert(candidates, "origin/" .. n)
    table.insert(candidates, n)
  end
  for _, name in ipairs(candidates) do
    if ref_exists(name, cwd) then
      return name
    end
  end
  return nil
end

-- Resolves base="auto" to the merge-base with trunk, so a feature branch shows
-- every change since it diverged (committed + working tree). Falls back to HEAD
-- when there is no trunk or we're sitting on it.
local function auto_base(cfg, cwd)
  if not has_head(cwd) then
    return "HEAD"
  end
  local trunk = detect_trunk(cfg, cwd)
  if not trunk then
    return "HEAD"
  end
  local code, mb = run({ "git", "merge-base", trunk, "HEAD" }, cwd)
  if code ~= 0 or mb == "" then
    return "HEAD"
  end
  return (mb:gsub("%s+$", ""))
end

-- Returns the concatenated unified diff text for cfg.base.
function M.diff(cfg, cwd)
  local requested = cfg.base or "auto"
  local base = requested
  local ctx = tostring(cfg.context_lines or 3)
  local args = {
    "git", "--no-optional-locks", "-c", "core.quotepath=false",
    "diff", "--no-color", "--no-ext-diff", "-U" .. ctx,
  }

  if base == "auto" then
    base = auto_base(cfg, cwd)
  end

  -- Brand-new repo with no commits: diff against the empty tree so everything
  -- shows up as added rather than erroring on a missing HEAD.
  if base == "HEAD" and not has_head(cwd) then
    base = EMPTY_TREE
  end

  for _, tok in ipairs(vim.split(base, "%s+", { trimempty = true })) do
    table.insert(args, tok)
  end

  local code, out, err = run(args, cwd)
  if code ~= 0 then
    error("tack: `git diff` failed: " .. err)
  end
  local text = out

  -- Untracked files only make sense for a working-tree review.
  local working_tree = requested == "auto" or requested == "HEAD"
  if cfg.include_untracked and working_tree then
    local _, list = run({ "git", "ls-files", "--others", "--exclude-standard", "-z" }, cwd)
    for _, f in ipairs(vim.split(list, "\0", { trimempty = true })) do
      -- `--no-index` exits non-zero when files differ; capture stdout anyway.
      local _, d = run({
        "git", "--no-optional-locks", "-c", "core.quotepath=false",
        "diff", "--no-color", "--no-index", "--", "/dev/null", f,
      }, cwd)
      if d and d ~= "" then
        text = text .. d
      end
    end
  end

  return text
end

return M
