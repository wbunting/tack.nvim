-- Configuration defaults and merge logic for tack.nvim.
local M = {}

M.defaults = {
  -- Diff target. Working tree is always compared against this.
  --   "auto"        -> merge-base with trunk: everything since you branched,
  --                    committed + uncommitted (falls back to HEAD on trunk)
  --   "HEAD"        -> only uncommitted changes (staged + unstaged)
  --   "main"        -> working tree vs a ref
  --   "main...dev"  -> a symmetric range
  base = "auto",

  -- Trunk branch candidates for base="auto" (origin's default branch is tried
  -- first, then these, preferring their origin/ remotes).
  trunk = { "main", "master", "trunk" },

  -- Where review comments are persisted. Relative paths resolve against the
  -- git root (falling back to cwd). This is the file your agent reads.
  sidecar = ".tack/review.json",

  -- Author stamped onto comments you create.
  author = "user",

  -- Context lines passed to `git diff -U`.
  context_lines = 3,

  -- Include untracked files in working-tree reviews (matches hunk.dev).
  include_untracked = true,

  -- Treesitter syntax highlighting of the code (composited over diff colors).
  syntax = true,

  -- Diff layout: "split" (side-by-side old | new) or "unified" (single buffer).
  view = "split",

  -- Window used to show the review: "tab" | "vsplit" | "split" | "current".
  -- (For view="split", "tab" opens the two panes in a new tab; otherwise they
  -- replace/split the current window.)
  layout = "tab",

  -- Ask for an optional rationale after the summary prompt.
  prompt_rationale = false,

  signs = {
    comment = "▌",                 -- sign-column marker on commented lines
    comment_hl = "DiagnosticInfo",
  },

  virt = {
    prefix = "💬 ",                -- end-of-line virtual text prefix
    hl = "Comment",
  },

  keymaps = {
    comment      = "c",   -- visual: comment selection / normal: comment current line
    remove       = "dc",  -- remove comment under cursor
    list         = "gc",  -- open all comments in quickfix
    reload       = "R",   -- re-run diff
    next_hunk    = "]h",
    prev_hunk    = "[h",
    next_comment = "]c",
    prev_comment = "[c",
    quit         = "q",
  },
}

M._config = nil

function M.setup(opts)
  M._config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M._config
end

function M.get()
  if not M._config then
    M._config = vim.deepcopy(M.defaults)
  end
  return M._config
end

return M
