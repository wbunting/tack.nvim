// @ts-nocheck
// tack — pi extension
//
// Injects any open .tack/review.json comments as silent context before each
// turn, so pi addresses the review comments you left in Neovim. Comments drop
// out of context once their "status" is "resolved". Mirror of the tack
// UserPromptSubmit hook (Claude Code / Codex) and the opencode plugin.
//
// Install: symlink into pi's auto-discovered extensions dir, e.g.
//   ln -s <repo>/agents/pi/tack.ts ~/.pi/agent/extensions/tack.ts
import fs from "node:fs";
import path from "node:path";

function findSidecar(start) {
  let d = path.resolve(start);
  for (;;) {
    const cand = path.join(d, ".tack", "review.json");
    if (fs.existsSync(cand)) return cand;
    if (fs.existsSync(path.join(d, ".git"))) return null;
    const parent = path.dirname(d);
    if (parent === d) return null;
    d = parent;
  }
}

function buildContext(dir) {
  const p = findSidecar(dir || process.cwd());
  if (!p) return null;
  let doc;
  try {
    doc = JSON.parse(fs.readFileSync(p, "utf8"));
  } catch {
    return null;
  }
  const open = (doc.comments || []).filter((c) => c.status !== "resolved");
  if (!open.length) return null;

  const lines = open.map((c, i) => {
    const side = c.side || (c.newLine ? "new" : "old");
    const line = c.newLine || c.oldLine || c.lineStart || "?";
    const span = c.lineStart && c.lineEnd && c.lineEnd !== c.lineStart ? `-${c.lineEnd}` : "";
    let e = `${i + 1}. ${c.filePath || "?"}:${line}${span} (${side}) — ${(c.summary || "").trim()}`;
    if (c.rationale) e += `\n   rationale: ${String(c.rationale).trim()}`;
    return e;
  });

  return (
    `The user left ${open.length} open code-review comment(s) via tack.nvim ` +
    `(source of truth: .tack/review.json). Treat each as a request anchored to that ` +
    `file and line. After you address one, mark it resolved by setting its "status" to ` +
    `"resolved" in that JSON file (leave the others intact; do not delete the file).\n\n` +
    lines.join("\n")
  );
}

const TACK_PROMPT =
  "Address the open tack review comments for this repo (.tack/review.json). " +
  'For each comment whose status is not "resolved": open its filePath at ' +
  "lineStart..lineEnd, make the change its summary (and rationale) describe, then set " +
  'that comment\'s status to "resolved" in .tack/review.json (leave the other comments ' +
  "intact; do not delete the file). Ask if anything is ambiguous, and summarize what you " +
  "changed by file when done.";

export default function tackExtension(pi) {
  // Auto-inject open comments as silent context before every turn.
  pi.on("before_agent_start", async () => {
    const content = buildContext(process.cwd());
    if (!content) return;
    return {
      message: {
        customType: "tack-review-comments",
        content,
        display: false,
      },
    };
  });

  // /tack — trigger the agent to act on the injected comments.
  pi.registerCommand?.("tack", {
    description: "Address open tack review comments (.tack/review.json)",
    handler: async (args) => {
      const extra = (args || "").trim();
      pi.sendUserMessage(extra ? `${TACK_PROMPT}\n\nAdditional instructions: ${extra}` : TACK_PROMPT);
    },
  });
}
