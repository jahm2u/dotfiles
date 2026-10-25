#!/usr/bin/env python3
"""agents_json.py -- print the ux-video-review helper agents as a `claude --agents` JSON.

    claude --strict-mcp-config --agents "$(python3 agents_json.py)" ...

Agents passed this way keep their own MCP servers under --strict-mcp-config (frontmatter
agents in ~/.claude/agents lose them), so a builder with no MCP can still hand the browser
work to ux-evidence, whose headless, isolated Chrome is never the user's own browser.
"""
import json
from pathlib import Path

AGENTS = Path(__file__).resolve().parent.parent / "agents"
SERVERS = {
    # --isolated: a temp profile, deleted on exit; --headless: no window. Never --autoConnect,
    # which attaches to the user's own Chrome and asks them to allow it every time.
    "evidence-chrome": {"type": "stdio", "command": "sh",
                        "args": ["-c", 'B="$HOME/.cache/evidence-chrome/node_modules/.bin/chrome-devtools-mcp"; '
                                 '[ -x "$B" ] || npm i --silent --prefix "$HOME/.cache/evidence-chrome" '
                                 'chrome-devtools-mcp@1.12.0 >/dev/null 2>&1; exec "$B" --isolated --headless']},
}


def load(path):
    text = path.read_text(encoding="utf-8")
    _, head, body = text.split("---", 2)
    meta = {k.strip(): v.strip() for k, sep, v in (line.partition(":") for line in head.splitlines()) if sep}
    agent = {"description": meta["description"], "prompt": body.strip(), "model": meta.get("model", "inherit")}
    if "tools" in meta:
        agent["tools"] = [t.strip() for t in meta["tools"].split(",")]
    if "mcp" in meta:
        agent["mcpServers"] = [{name: SERVERS[name]} for name in (n.strip() for n in meta["mcp"].split(","))]
    return path.stem, agent


if __name__ == "__main__":
    print(json.dumps(dict(load(p) for p in sorted(AGENTS.glob("*.md")))))
