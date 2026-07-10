// tack — opencode plugin
//
// Injects any open .tack/review.json comments into the system prompt on every
// turn, so the agent addresses the review comments you left in Neovim without
// you having to ask. Comments disappear from context once their "status" is
// "resolved". Mirror of the tack UserPromptSubmit hook used by Claude Code and
// Codex.
//
// Install: referenced from ~/.config/opencode/opencode.json "plugin" array, e.g.
//   "plugin": [ "./plugins/tack/plugin.js" ]
// (symlink ~/.config/opencode/plugins/tack -> this directory).
import fs from "node:fs";
import path from "node:path";

// Walk up from `start` to the git root; return the first .tack/review.json.
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

export const TackPlugin = async ({ directory }) => {
  return {
    "experimental.chat.system.transform": async (_input, output) => {
      if (!output || !Array.isArray(output.system)) return;
      const ctx = buildContext(directory);
      if (ctx) output.system.push(ctx);
    },
  };
};

export default TackPlugin;
