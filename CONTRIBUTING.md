# Contributing to tack.nvim

Thanks for helping out. tack aims to stay small and dependency-free (pure Lua +
`git`), so most changes are self-contained.

## Layout

```
lua/tack/     config git parse render store comment ui init syntax annotate
plugin/tack.lua   zero-config commands + highlights
agents/           auto-inject hooks/plugins + /tack command per agent
doc/tack.txt      vim help
```

## Running it

Load from the working tree without installing:

```lua
vim.opt.runtimepath:append("~/.local/src/tack.nvim")
require("tack").setup({})
```

## Smoke test (headless)

The same check CI runs:

```sh
nvim --headless -u NONE \
  -c "lua vim.opt.rtp:append('.')" \
  -c "lua for _,m in ipairs({'config','git','parse','render','store','comment','ui','syntax','annotate'}) do require('tack.'..m) end" \
  -c "lua require('tack').setup({}); assert(vim.fn.exists(':TackReview')==2)" \
  -c "lua print('ok')" -c "qa!"
```

A manual end-to-end: make a change in a scratch git repo, `:TackReview`, select a
few lines, `c`, comment, then check `.tack/review.json`.

## Reporting bugs

Please include:

- Neovim version (`nvim --version`) and OS.
- A minimal repro: a tiny git repo + the exact steps.
- What you expected vs what happened (and any `:messages`).

## Style

- Match the surrounding code; keep it dependency-free.
- Remember: `hunk` in the code means a **diff hunk** (a domain term), not the old
  project name — don't rename those.
