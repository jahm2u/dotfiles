#!/usr/bin/env python3
"""Render a progress snapshot from a session handoff.

Reads `<repo>/_bmad/handoff/HANDOFF-latest.json` (already written by the handoff
skill) and prints a compact, bar-charted view of where the session stands:

    - a progress bar over `problems` by status (fixed / workaround / open),
    - "Still open / in flight" = open problems + workarounds + next_steps,
    - "Needs your decision" = open_questions (the human's call).

Deliberately tiny, deterministic, stdlib-only — the same signal every time,
computed from the JSON rather than re-narrated by the model. Designed to be the
FIRST thing shown when a handoff completes, so the human sees the shape of the
work before the prose.

Usage:
    python3 summarize_progress.py [<repo_root>]   # defaults to cwd

Exit code: 0 on success, 1 if the handoff JSON is missing or unreadable (so a
handoff is never silently reported as "no progress").
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

if __package__:
    from scripts.handoff import constants as C
else:  # pragma: no cover - exercised only via direct CLI invocation
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from scripts.handoff import constants as C

BAR_WIDTH = 24

# Problem statuses, in the order they render, with a glyph each. Anything a
# handoff writes that is not one of these is bucketed as "open" (the safe read:
# unknown status is not done).
DONE_STATUSES = ("fixed",)
PARTIAL_STATUSES = ("workaround",)


def _load(cwd: str) -> dict:
    path = C.handoff_dir(cwd) / C.HANDOFF_JSON_NAME
    if not path.exists():
        raise FileNotFoundError(f"no handoff JSON at {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def _as_list(value) -> list:
    return value if isinstance(value, list) else []


def _status_of(problem) -> str:
    if not isinstance(problem, dict):
        return "open"
    status = str(problem.get("status", "open")).strip().lower()
    if status in DONE_STATUSES:
        return "fixed"
    if status in PARTIAL_STATUSES:
        return "workaround"
    return "open"


def _bar(fixed: int, partial: int, total: int) -> str:
    """A single-line stacked bar: █ fixed, ▓ workaround, ░ remaining."""
    if total <= 0:
        return "░" * BAR_WIDTH + "  (no tracked problems)"
    f = round(BAR_WIDTH * fixed / total)
    p = round(BAR_WIDTH * partial / total)
    # Never let rounding overrun the width or hide a non-zero remainder.
    f = min(f, BAR_WIDTH)
    p = min(p, BAR_WIDTH - f)
    r = BAR_WIDTH - f - p
    pct = round(100 * fixed / total)
    return f"{'█' * f}{'▓' * p}{'░' * r}  {pct}% done ({fixed}/{total})"


def _oneline(text, limit: int = 100) -> str:
    s = " ".join(str(text).split())
    return s if len(s) <= limit else s[: limit - 1] + "…"


def render(handoff: dict) -> str:
    problems = _as_list(handoff.get("problems"))
    fixed = [p for p in problems if _status_of(p) == "fixed"]
    partial = [p for p in problems if _status_of(p) == "workaround"]
    still_open = [p for p in problems if _status_of(p) == "open"]
    next_steps = _as_list(handoff.get("next_steps"))
    questions = _as_list(handoff.get("open_questions"))
    open_prs = _as_list(handoff.get("current_state", {}).get("open_prs")) \
        if isinstance(handoff.get("current_state"), dict) else []

    out: list[str] = []
    out.append("── Session progress " + "─" * 40)
    mission = handoff.get("mission")
    if mission:
        out.append(_oneline(mission, 140))
        out.append("")
    out.append(_bar(len(fixed), len(partial), len(problems)))
    out.append(
        f"  █ done {len(fixed)}   ▓ workaround {len(partial)}   ░ open {len(still_open)}"
    )
    out.append("")

    if fixed:
        out.append(f"✅ Done ({len(fixed)})")
        for p in fixed:
            out.append(f"   • {_oneline(p.get('problem', p))}")
        out.append("")

    remaining = partial + still_open
    if remaining or next_steps:
        out.append("🚧 Still open / next")
        for p in partial:
            out.append(f"   ~ {_oneline(p.get('problem', p))}  [workaround]")
        for p in still_open:
            out.append(f"   • {_oneline(p.get('problem', p))}")
        for step in next_steps:
            out.append(f"   → {_oneline(step)}")
        out.append("")

    if open_prs:
        out.append("🔀 Open PRs")
        for pr in open_prs:
            out.append(f"   • {_oneline(pr)}")
        out.append("")

    out.append("🙋 Needs your decision")
    if questions:
        for q in questions:
            out.append(f"   ? {_oneline(q, 140)}")
    else:
        out.append("   (none — nothing is blocked on you)")
    out.append("─" * 60)
    return "\n".join(out)


def main(argv: list[str]) -> int:
    cwd = argv[1] if len(argv) > 1 else "."
    try:
        handoff = _load(cwd)
    except (FileNotFoundError, OSError, json.JSONDecodeError) as exc:
        print(f"[handoff] progress summary unavailable: {exc}", file=sys.stderr)
        return 1
    print(render(handoff))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
