#!/usr/bin/env python3
"""Append a session's learnings to the durable kaizen signal log.

Ported from alter-ego AE-0216 (smart handoff) with VERBATIM logic; only the
state root ("_bmad/handoff" via constants) is adapted for this module.

The `/handoff` skill calls this after writing `HANDOFF-latest.json`. It
distils the handoff's learning-bearing fields (problems + root causes,
landmines, decisions) into one compact record appended to
`_bmad/handoff/learnings-log.jsonl` — the append-only signal that the kaizen
`session` mode (P5) mines across sessions to propose systemic improvements.

This is deliberately a tiny, deterministic, stdlib-only helper (not model logic)
so the signal is captured the same way every time. Idempotent per handoff:
re-running for the same `created_at` does not double-append.

Usage:
    python3 log_learnings.py [<repo_root>]   # defaults to cwd
Exit code is always 0 unless given an unreadable handoff (1), so a handoff write
is never silently dropped without signal.
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

# Fields lifted from the handoff JSON into the learnings record (the kaizen
# signal). Everything else (files_touched, verification, ...) is session
# bookkeeping, not improvement signal.
LEARNING_FIELDS = ("created_at", "mission", "problems", "landmines", "decisions")

# The subset whose presence makes a handoff worth logging at all. `created_at`
# and `mission` are bookkeeping — a record carrying only those is noise.
MINEABLE_FIELDS = ("problems", "landmines", "decisions")


def _logged_created_ats(log_path: Path) -> set[str]:
    """Every `created_at` already present in the log.

    Scans the WHOLE file, not just the last record: replaying an older handoff
    after a newer one has been logged still has to be a no-op, and comparing
    against the tail alone would happily append the duplicate.
    """
    if not log_path.exists():
        return set()
    try:
        lines = [ln for ln in log_path.read_text(encoding="utf-8").splitlines() if ln.strip()]
    except (OSError, UnicodeDecodeError):
        return set()
    seen: set[str] = set()
    for line in lines:
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(record, dict):
            continue
        created_at = record.get("created_at")
        if isinstance(created_at, str) and created_at:
            seen.add(created_at)
    return seen


def _distil(handoff: dict[str, object]) -> dict[str, object]:
    return {key: handoff.get(key) for key in LEARNING_FIELDS if handoff.get(key)}


def run(repo_root: str) -> int:
    directory = C.handoff_dir(repo_root)
    handoff_json = directory / C.HANDOFF_JSON_NAME
    if not handoff_json.is_file():
        sys.stderr.write(f"no handoff json at {handoff_json}\n")
        return 1
    try:
        handoff = json.loads(handoff_json.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        sys.stderr.write(f"unreadable handoff json: {exc}\n")
        return 1
    if not isinstance(handoff, dict):
        sys.stderr.write("handoff json is not an object\n")
        return 1

    record = _distil(handoff)
    # `decisions` is a LEARNING_FIELDS member and durable kaizen signal in its own
    # right: a session that hit no problem but settled an architectural decision
    # must still reach the feed.
    if not any(record.get(field) for field in MINEABLE_FIELDS):
        # Nothing worth mining; do not pollute the signal log.
        sys.stderr.write("no learnings (problems/landmines/decisions) to log\n")
        return 0

    log_path = directory / C.LEARNINGS_LOG_NAME
    created_at = record.get("created_at")
    try:
        directory.mkdir(parents=True, exist_ok=True)
        # The duplicate check and the append are one critical section: two
        # concurrent runs would otherwise both read a log without this
        # `created_at` and both append it.
        with C.exclusive_lock(log_path):
            if created_at and created_at in _logged_created_ats(log_path):
                sys.stderr.write("learnings for this handoff already logged (idempotent)\n")
                return 0
            with log_path.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(record, ensure_ascii=False) + "\n")
    except OSError as exc:
        sys.stderr.write(f"could not append to learnings log: {exc}\n")
        return 1
    sys.stderr.write(f"logged learnings to {log_path}\n")
    return 0


def main() -> int:
    repo_root = sys.argv[1] if len(sys.argv) > 1 else str(Path.cwd())
    return run(repo_root)


if __name__ == "__main__":
    sys.exit(main())
