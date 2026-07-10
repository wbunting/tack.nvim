# Changelog

All notable changes to tack.nvim are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Side-by-side (default) and unified diff review, built from the parsed `git diff`
  so every rendered row maps to an exact `(file, side, line)` anchor.
- `base = "auto"` — diff against the merge-base with trunk (all changes since you
  branched, committed + working tree); falls back to `HEAD` on trunk.
- Treesitter syntax highlighting composited over background-only diff highlights.
- Visual-mode comments on diffs **and** on any file buffer, persisted to a
  `.tack/review.json` sidecar with real file/line anchors.
- `:TackReview`, `:TackReload`, `:TackComment`, `:TackRemove`, `:TackComments`,
  `:TackClear`; buffer-local review keymaps; quickfix list; hunk/comment nav.
- Agent integrations in [`agents/`](agents/): auto-inject open comments +
  `/tack` command for Claude Code, Codex, OpenCode, and pi.

[Unreleased]: https://github.com/wbunting/tack.nvim/commits/main
