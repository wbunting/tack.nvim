---
description: Address open tack review comments (from .tack/review.json)
---
Address the open tack review comments for this repo.

They live in `.tack/review.json` at the repo root. The open ones (`status` !=
`"resolved"`) may already be injected into your context by the tack hook/plugin;
if not, read that file now.

For each open comment:
1. Open its `filePath` and go to `lineStart`..`lineEnd` (use `side` / `newLine` /
   `oldLine` to anchor the exact location).
2. Treat `summary` (and any `rationale`) as the instruction, and make the change.
3. Mark it resolved: set that comment's `status` to `"resolved"` in
   `.tack/review.json`. Leave the other comments intact; do not delete the file.

If a comment is ambiguous, ask before guessing. When finished, summarize what you
changed, grouped by file.
