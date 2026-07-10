#!/usr/bin/env python3
"""tack UserPromptSubmit hook — for Claude Code and Codex.

Both agents fire a UserPromptSubmit hook with the same JSON contract: they send
{"cwd": ..., "prompt": ...} on stdin and read back
{"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": ...}}.

This reads the project's .tack/review.json and, if there are any open review
comments, injects them so the agent addresses them on this turn. When every
comment is resolved it injects nothing.
"""
import json
import os
import sys


def find_sidecar(start):
    """Walk up from `start` to the git root, returning the first
    .tack/review.json found (or None)."""
    d = os.path.abspath(start)
    while True:
        cand = os.path.join(d, ".tack", "review.json")
        if os.path.isfile(cand):
            return cand
        if os.path.isdir(os.path.join(d, ".git")):
            return None  # reached the repo root without a sidecar
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def render(comments):
    out = []
    for i, c in enumerate(comments, 1):
        side = c.get("side") or ("new" if c.get("newLine") else "old")
        line = c.get("newLine") or c.get("oldLine") or c.get("lineStart") or "?"
        ls, le = c.get("lineStart"), c.get("lineEnd")
        span = "-%s" % le if ls and le and le != ls else ""
        entry = "%d. %s:%s%s (%s) — %s" % (
            i, c.get("filePath", "?"), line, span, side, (c.get("summary") or "").strip()
        )
        if c.get("rationale"):
            entry += "\n   rationale: %s" % str(c["rationale"]).strip()
        out.append(entry)
    return "\n".join(out)


def main():
    cwd = os.getcwd()
    try:
        raw = sys.stdin.read()
        if raw.strip():
            cwd = json.loads(raw).get("cwd") or cwd
    except Exception:
        pass

    path = find_sidecar(cwd)
    if not path:
        return
    try:
        with open(path) as fh:
            doc = json.load(fh)
    except Exception:
        return

    comments = [c for c in doc.get("comments", []) if c.get("status") != "resolved"]
    if not comments:
        return

    context = (
        "The user left %d open code-review comment(s) via tack.nvim "
        "(source of truth: .tack/review.json). Treat each as a request anchored "
        "to that file and line. After you address one, mark it resolved by setting "
        'its "status" to "resolved" in that JSON file (leave the others intact; do '
        "not delete the file).\n\n%s"
    ) % (len(comments), render(comments))

    json.dump(
        {"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": context}},
        sys.stdout,
    )


if __name__ == "__main__":
    main()
