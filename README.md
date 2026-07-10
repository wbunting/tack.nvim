<!-- markdownlint-disable MD033 MD041 -->
<h1 align="center">📌 tack.nvim</h1>

<p align="center">
  <b>Review a clean diff in Neovim, drop comments on the lines you care about, and hand them to your AI coding agent.</b>
</p>

<p align="center">
  Select code → leave a note → your agent picks it up from a plain <code>.tack/review.json</code> and does the work.
  Comment on a diff <i>or any file</i> to point an agent at an exact location.
</p>

<p align="center">
  <a href="https://github.com/wbunting/tack.nvim/actions/workflows/ci.yml"><img src="https://github.com/wbunting/tack.nvim/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/Neovim-0.10%2B-57A143?logo=neovim&logoColor=white" alt="Neovim 0.10+">
  <img src="https://img.shields.io/badge/Lua-2C2D72?logo=lua&logoColor=white" alt="Lua">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="License GPL-3.0"></a>
  <a href="https://github.com/wbunting/tack.nvim/stargazers"><img src="https://img.shields.io/github/stars/wbunting/tack.nvim?style=social" alt="Stars"></a>
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#configuration">Configuration</a> ·
  <a href="#commands">Commands</a> ·
  <a href="#comment-on-any-file">Examples</a> ·
  <a href="#agent-integration">Agent integration</a> ·
  <a href="#faq">FAQ</a>
</p>

---

## The loop

```
:TackReview          clean side-by-side diff of everything since you branched
V  (select lines)    in the diff, or in any file
c  → type a note     ▌ marker + note appear on the line
                     → saved to .tack/review.json
"do my tack comments"  agent reads the sidecar, makes the change, marks it resolved
```

No daemon, no background process. Comments are a plain JSON file on disk — they
survive restarts, and any agent (or you) can read them.

## Demo

<p align="center">
  <img src="assets/demo.gif" alt="tack.nvim demo: select diff lines, leave a comment, and resolve it with an agent">
</p>

What the side-by-side view looks like (syntax colors preserved over the diff):

```
  old                                new
  42 - return result.rows            42 + const rows = result.rows ?? []
                                      43 + return rows          ▌ 💬 handle the null case
  43   }                             44   }
```

## Features

- **Clean side-by-side (or unified) diff** built from `git diff` — removed left,
  added right, paired row-for-row and scrollbound.
- **Real syntax highlighting** layered *over* the red/green diff backgrounds via
  Treesitter (composited, not either/or), with graceful fallback when a parser
  isn't installed.
- **Point the agent at exactly what you mean** — visual-select a block (in the
  diff *or* any file) and write the instruction right on it. The agent gets the
  precise file + line range, not a vague "somewhere in `App.tsx`".
- **`base = "auto"`** shows everything since you branched off `main`/`master`
  (committed **and** working-tree), not just uncommitted changes.
- **Agent-agnostic, push or pull** — the sidecar is a plain local file any tool or
  script can read (no API, no lock-in). Optional hooks also auto-inject open
  comments into Claude Code, Codex, OpenCode, and pi every turn, with a `/tack`
  command to act.
- **Zero startup cost** — pure Lua + `git`, no runtime dependencies; lazy-loads on
  its commands/keys. Diffs and Treesitter parsing happen on demand when you review.

## Why tack?

- **You already read diffs in Neovim.** [hunk.dev](https://hunk.dev) has a lovely
  clean diff + inline comments, but its state is bound to a live TUI and is
  ephemeral. tack recreates the part that matters — *read a clean diff, select
  lines, comment, hand to an agent* — natively, with comments persisted to a repo
  file.
- **Point the agent precisely.** Instead of describing "in `App.tsx`, around the
  query…", select the lines and write the instruction on them. The agent gets the
  exact path + line range.
- **Batch your review.** Leave all your comments first, then trigger the agent
  once — no edits shifting under you mid-review. Comments drop out of context as
  they're resolved.

## Requirements

- **Neovim ≥ 0.10** (uses `vim.system`, `vim.uv`, `vim.islist`).
- **git** in `PATH`.
- *Optional:* the Treesitter parser for a language enables syntax colors in its
  files (`:TSInstall tsx`, etc.). Without it you still get diff colors.

No other plugins required. Run `:checkhealth tack` to verify git, your Neovim
version, and Treesitter.

## Install

<details open><summary><b>lazy.nvim</b></summary>

```lua
{
  "wbunting/tack.nvim",
  cmd = { "TackReview", "TackReload", "TackComments", "TackComment", "TackClear", "TackRemove" },
  keys = {
    { "<leader>Rr", "<cmd>TackReview<cr>", desc = "Review diff" },
    { "<leader>RR", "<cmd>TackReload<cr>", desc = "Reload review" },
    { "<leader>Rl", "<cmd>TackComments<cr>", desc = "List comments" },
    { "<leader>Rc", "<cmd>TackComment<cr>", mode = "n", desc = "Comment line" },
    { "<leader>Rc", ":<C-u>'<,'>TackComment<cr>", mode = "x", desc = "Comment selection" },
    { "<leader>Rx", "<cmd>TackRemove<cr>", mode = "n", desc = "Remove comment" },
  },
  opts = {
    view = "split", -- "split" (side-by-side) | "unified"
  },
}
```

</details>

<details><summary><b>mini.deps</b></summary>

```lua
add({ source = "wbunting/tack.nvim" })
require("tack").setup({})
```

</details>

<details><summary><b>vim-plug</b></summary>

```vim
Plug 'wbunting/tack.nvim'
" then, in Lua: require('tack').setup({})
```

</details>

Calling `setup()` is optional — the `:Tack*` commands work with defaults out of
the box. `setup()` (or lazy `opts`) is only needed to override configuration.

## Quickstart

1. Open a repo with changes.
2. `:TackReview` (or `<leader>Rr`).
3. `V` to select lines on the **right** pane (new code) → press `c` → type a note.
4. Tell your agent: *"do my tack comments"* (or run `/tack` — see
   [Agent integration](#agent-integration)).

> **Tip:** alias it — `alias td='nvim +TackReview'` (`td` = "tack diff") opens the
> review straight from your shell.

## Configuration

Defaults (override any subset via `setup()` / lazy `opts`):

```lua
require("tack").setup({
  base = "auto",                 -- diff target: merge-base with trunk, "HEAD", a ref, or "a...b" range
  trunk = { "main", "master", "trunk" }, -- candidates for base="auto" (origin default tried first)
  sidecar = ".tack/review.json", -- comment store, resolved against the git root
  author = "user",               -- stamped on comments you create
  context_lines = 3,             -- git diff -U context
  include_untracked = true,      -- show untracked files in working-tree reviews
  syntax = true,                 -- Treesitter colors composited over diff backgrounds
  view = "split",                -- "split" (side-by-side old | new) | "unified"
  layout = "tab",                -- "tab" | "vsplit" | "split" | "current"
  prompt_rationale = false,      -- ask for an optional rationale after the summary
  signs = { comment = "▌", comment_hl = "DiagnosticInfo" },
  virt  = { prefix = "💬 ", hl = "Comment" },
  keymaps = {                    -- buffer-local, inside the review buffer
    comment = "c", remove = "dc", list = "gc", reload = "R",
    next_hunk = "]h", prev_hunk = "[h",
    next_comment = "]c", prev_comment = "[c", quit = "q",
  },
})
```

### `base` values

| value | shows |
| --- | --- |
| `"auto"` (default) | everything since you branched off trunk — committed **and** uncommitted. Falls back to `HEAD` when you're on trunk. |
| `"HEAD"` | only uncommitted changes (staged + unstaged) |
| `"main"` | working tree vs a ref |
| `"main...dev"` | a symmetric range |

## Commands

| Command | Description |
| --- | --- |
| `:TackReview [base]` | Open the diff review. `base` overrides the configured default for this session. |
| `:TackReload` | Re-run the diff and repaint (keeps your comments). |
| `:[range]TackComment` | Comment on a range — in the diff **or any file buffer**. |
| `:TackRemove` | Remove the comment under the cursor. |
| `:TackComments` | Put every comment into the quickfix list (jumps to real source). |
| `:TackClear [file]` | Clear all comments, or just those for one file. |

## Keymaps (inside the review buffer)

Buffer-local, so they never shadow your global maps:

| Key | Action |
| --- | --- |
| `c` | Comment the visual selection / current line |
| `dc` | Remove the comment under the cursor |
| `gc` | Open all comments in the quickfix list |
| `R` | Reload the diff |
| `]h` / `[h` | Next / previous hunk |
| `]c` / `[c` | Next / previous comment |
| `q` | Close the review |

Comment on the **right** pane for new code, the **left** pane for removed code.

## Lua API

```lua
require("tack").review(base)   -- open the review (base optional)
require("tack").reload()       -- re-run the diff
require("tack").comment(l1, l2)-- comment on a line range in the current buffer
require("tack").remove()       -- remove the comment under the cursor
require("tack").list()         -- comments -> quickfix
require("tack").clear(file)    -- clear comments (all, or for `file`)
require("tack").setup(opts)    -- configure
```

## Highlight groups

Linked with `default = true`, so override freely. `Add`/`Delete` are derived as
**background-only** from `DiffAdd`/`DiffDelete` so syntax foreground shows through.

`TackFileHeader`, `TackHunkHeader`, `TackAdd`, `TackDelete`, `TackLineNr`,
`TackFiller`, `TackCommentSign`, `TackCommentText`.

## Comment on any file

The comment workflow isn't limited to diffs. Open any file, visual-select some
lines, `:'<,'>TackComment` (or bind a key), and it's saved to the same
`.tack/review.json` with the file's real line numbers — a lightweight "agent, work
here" pointer. Markers redraw when you open the file, and `:TackRemove` clears the
one under the cursor.

```lua
-- suggested global maps (the review buffer already has its own c / dc)
vim.keymap.set("x", "<leader>Rc", ":<C-u>'<,'>TackComment<cr>", { desc = "tack: comment selection" })
vim.keymap.set("n", "<leader>Rc", "<cmd>TackComment<cr>",        { desc = "tack: comment line" })
vim.keymap.set("n", "<leader>Rx", "<cmd>TackRemove<cr>",         { desc = "tack: remove comment" })
```

## The sidecar: `.tack/review.json`

Every comment is appended here (path configurable), anchored by real file + line:

```json
{
  "version": 1,
  "comments": [
    {
      "id": "c1782-abcd-1",
      "filePath": "src/App.tsx",
      "side": "new",
      "newLine": 372,
      "lineStart": 372,
      "lineEnd": 374,
      "summary": "handle the null case here",
      "rationale": "db.query can return undefined",
      "author": "user",
      "status": "open",
      "createdAt": "2026-07-10T05:03:27Z"
    }
  ]
}
```

Add `.tack/` to your `.gitignore` unless you want to commit reviews.

## Agent integration

The point of the sidecar: your coding agent reads it. Two ways, both in
[`agents/`](agents/):

1. **Auto-inject (push)** — a small hook/plugin injects any **open** comments
   (`status != "resolved"`) into the agent's context every turn. They drop out
   once resolved.
2. **`/tack` command** — a prompt that tells the agent to address the open
   comments and mark each resolved.

| Agent | Auto-inject | `/tack` |
| --- | --- | --- |
| **Claude Code** | `UserPromptSubmit` hook (`settings.json`) | `commands/tack.md` |
| **Codex** | `UserPromptSubmit` hook (`hooks.json`) | `prompts/tack.md` |
| **OpenCode** | plugin (`experimental.chat.system.transform`) | `command/tack.md` |
| **pi** | extension (`before_agent_start`) | `registerCommand` |

See [`agents/README.md`](agents/README.md) for one-command install per agent. Not
on those agents? Any tool can read `.tack/review.json` — the schema is above, and
[`agents/tack-hook.py`](agents/tack-hook.py) is a ~60-line reference.

## Integrations

- **lazy.nvim** — see [Install](#install).
- **which-key.nvim** — the suggested maps live under `<leader>R` ("+Review") and
  carry `desc`s, so they group automatically.

### Planned

- Telescope / fzf-lua / snacks picker over open comments.
- A `lualine` component for the open-comment count.

PRs welcome.

## FAQ

**`:TackReview` shows nothing on my branch.** Everything is committed, and the old
default only showed *uncommitted* changes. `base` now defaults to `"auto"` (diff
vs the merge-base with trunk) — update tack, or use `:TackReview main`.

**`.tsx` (or some language) has no colors.** Install that language's Treesitter
parser: `:TSInstall tsx`. `syntax = false` disables highlighting entirely.

**Does it need a GitHub remote or the hunk.dev CLI?** No. Just local `git`. tack
is standalone and does not depend on hunk.dev.

**Can I use one buffer instead of side-by-side?** Yes: `view = "unified"`.

**Will `c` override my change operator?** No — the review keymaps are
buffer-local to the review buffer only.

**Where do comments live / how do I wipe them?** `.tack/review.json` at the git
root. `:TackClear` wipes all, `:TackClear path/to/file` just one file's.

## Contributing

- Repro/tests run headless, e.g.:
  ```sh
  nvim --headless -u NONE \
    -c "lua vim.opt.rtp:append('.')" \
    -c "lua require('tack').setup({}); print(vim.fn.exists(':TackReview'))" \
    -c "qa!"
  ```
- Please include a minimal repro (a tiny git repo + the steps) on bug reports.
- Keep it dependency-free (pure Lua + `git`).

## License

GPL-3.0 — see [LICENSE](LICENSE). Copyright (C) 2026 Will Bunting.
