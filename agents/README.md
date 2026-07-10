# tack — agent integrations

Push tack review comments into your coding agent automatically, plus a `/tack`
command to tell it to act.

Two pieces per agent:

1. **Auto-inject** — a hook/plugin that reads `.tack/review.json` and injects any
   **open** comments (`status != "resolved"`) as context on every turn. Comments
   drop out once the agent marks them resolved.
2. **`/tack` command** — a prompt that says "address the open tack comments and
   mark each resolved," for when you want to trigger the agent explicitly.

The auto-inject and the command both point at the same `.tack/review.json` that
`tack.nvim` writes, so this works whether you comment on a diff (`:TackReview`) or
on any file (`:TackComment`).

## Files

| File | Purpose |
|---|---|
| `tack-hook.py` | UserPromptSubmit hook — **Claude Code** and **Codex** (identical JSON contract) |
| `opencode/tack/plugin.js` | **OpenCode** plugin (`experimental.chat.system.transform`) |
| `pi/tack.ts` | **pi** extension (`before_agent_start`) |
| `commands/tack.md` | the shared `/tack` prompt, installed into each agent's command dir |

## Install

Let `TACK=/absolute/path/to/tack.nvim`.

### Claude Code
Auto-inject — add to `~/.claude/settings.json`:
```json
{ "hooks": { "UserPromptSubmit": [ { "hooks": [
  { "type": "command", "command": "$TACK/agents/tack-hook.py", "timeout": 15 }
] } ] } }
```
Command:
```sh
ln -s "$TACK/agents/commands/tack.md" ~/.claude/commands/tack.md
```

### Codex
Auto-inject — add to `~/.codex/config.toml`:
```toml
[[hooks.UserPromptSubmit]]
[[hooks.UserPromptSubmit.hooks]]
type = "command"
command = "/ABS/PATH/tack.nvim/agents/tack-hook.py"
timeout = 15
```
Command:
```sh
ln -s "$TACK/agents/commands/tack.md" ~/.codex/prompts/tack.md
```

### OpenCode
Auto-inject — symlink the plugin and register it in `~/.config/opencode/opencode.json`:
```sh
ln -s "$TACK/agents/opencode/tack" ~/.config/opencode/plugins/tack
# add "./plugins/tack/plugin.js" to the "plugin" array in opencode.json
```
Command:
```sh
ln -s "$TACK/agents/commands/tack.md" ~/.config/opencode/command/tack.md
```

### pi
Symlink the extension (auto-discovered) — it provides **both** the auto-inject
(`before_agent_start`) and the `/tack` command (`registerCommand` +
`sendUserMessage`), so there is no separate command file for pi:
```sh
ln -s "$TACK/agents/pi/tack.ts" ~/.pi/agent/extensions/tack.ts
```

## Uninstall

Remove the symlinks above, delete the `UserPromptSubmit` hook block from
`settings.json` / `config.toml`, and remove `./plugins/tack/plugin.js` from
`opencode.json`.
