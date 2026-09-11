#!/usr/bin/env python3
"""SessionStart hook: seed a fresh session with the latest handoff document.

Ported from alter-ego AE-0216 (smart handoff) with VERBATIM logic. Only the
state root ("_bmad/handoff" via constants) and the kaizen nudge wording
(the learnings review) are adapted for this module.

Reads the Claude Code SessionStart payload on stdin and, when appropriate, emits
``hookSpecificOutput.additionalContext`` containing the repo's latest handoff
(`_bmad/handoff/HANDOFF-latest.md`). This is the "smart compact" read-side:
after `/handoff` writes a curated document and the user runs `/clear` (or
opens a fresh session), the wiped context is re-seeded automatically.

Guarantees:
  * Never raises into the harness — any error degrades to a silent no-op (exit 0).
  * No-ops cleanly when `_bmad/handoff/` is absent (a non-harness project): the
    hook is installed globally and runs on EVERY project's session start.
  * Skips `source == "compact"` (same session already holds the context).
  * Dedupes per (handoff-content, session) so a session is seeded at most once per
    handoff; writing a NEW handoff (different content hash) resets the dedupe so
    every session can pick the new one up exactly once.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

# Allow running both as a module (tests) and as a bare script (hook command).
if __package__:
    from scripts.handoff import constants as C
else:  # pragma: no cover - exercised only via direct CLI invocation
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from scripts.handoff import constants as C


def _read_payload() -> dict[str, str]:
    """Parse the hook stdin JSON; return an empty dict on any problem."""
    try:
        raw = sys.stdin.read()
    except (OSError, ValueError):
        return {}
    if not raw.strip():
        return {}
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


def _content_hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8", "replace")).hexdigest()[:16]


def _consumed_session_ids(consumed_path: Path, current_hash: str) -> set[str]:
    """Session ids already seeded with THIS handoff.

    The consumed file's first line is the handoff content hash. If it differs
    from the current handoff (a newer checkpoint was written), the prior record
    is stale and treated as empty so the new handoff is re-offered to everyone.
    """
    if not consumed_path.exists():
        return set()
    try:
        lines = consumed_path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return set()
    if not lines or lines[0].strip() != current_hash:
        return set()
    return {line.strip() for line in lines[1:] if line.strip()}


def _record_consumed(consumed_path: Path, current_hash: str, session_ids: set[str]) -> None:
    payload = "\n".join([current_hash, *sorted(session_ids)]) + "\n"
    try:
        # Rename-published: a reader must never observe a truncated file whose
        # first line no longer matches the hash, which reads as "stale" and
        # re-offers the handoff to every session.
        C.atomic_write_text(consumed_path, payload)
    except OSError:
        # Best-effort: failing to record dedupe state must not break injection.
        pass


def _frame(handoff_text: str, json_path: Path) -> str:
    """Wrap the handoff for injection, truncating overly large documents."""
    body = handoff_text
    if len(body) > C.MAX_INJECT_CHARS:
        body = body[: C.MAX_INJECT_CHARS] + (
            f"\n\n[... truncated — read the full handoff at {json_path} ...]"
        )
    return (
        "## Session handoff (auto-injected)\n\n"
        "A previous session checkpointed its state below. Treat it as the "
        "starting context for this session; the machine-readable twin is at "
        f"`{json_path}`.\n\n"
        f"{body}"
    )


def _emit(additional_context: str) -> None:
    output = {
        C.HOOK_OUTPUT_KEY: {
            C.HOOK_EVENT_NAME_KEY: C.SESSION_START_EVENT,
            C.ADDITIONAL_CONTEXT_KEY: additional_context,
        }
    }
    sys.stdout.write(json.dumps(output))


def _kaizen_nudge(cwd: str) -> str:
    """A one-line nudge to run kaizen when unreviewed learnings have piled up."""
    pending = C.pending_learnings_count(cwd)
    if pending <= 0:
        return ""
    sessions = "session" if pending == 1 else "sessions"
    return (
        f"\n\n---\n**Learnings pending:** {pending} {sessions} of unreviewed learnings "
        "in `_bmad/handoff/learnings-log.jsonl`. Worth skimming for recurring "
        "problems and landmines that should be promoted into project rules or "
        "CLAUDE.md. Nothing is created automatically."
    )


def _handoff_block(directory: Path, session_id: str) -> str:
    """Framed handoff to inject, or "" when none / already consumed by session."""
    handoff_md = directory / C.HANDOFF_MARKDOWN_NAME
    if not handoff_md.is_file():
        return ""
    try:
        handoff_text = handoff_md.read_text(encoding="utf-8")
    except OSError:
        return ""
    if not handoff_text.strip():
        return ""

    current_hash = _content_hash(handoff_text)
    consumed_path = directory / C.CONSUMED_FILE_NAME
    # Read-check-write under one lock: two concurrent SessionStart hooks would
    # otherwise both read the pre-existing set and the second write would drop
    # the first session's id, re-offering an already-consumed handoff.
    with C.exclusive_lock(consumed_path):
        consumed = _consumed_session_ids(consumed_path, current_hash)
        if session_id and session_id in consumed:
            return ""

        block = _frame(handoff_text, directory / C.HANDOFF_JSON_NAME)
        if session_id:
            consumed.add(session_id)
            _record_consumed(consumed_path, current_hash, consumed)
    return block


def run(payload: dict[str, str]) -> int:
    """Core logic. Returns the desired process exit code (always 0)."""
    # An empty/unparseable payload means malformed stdin — a real SessionStart
    # always sends a populated object. Do nothing rather than guess from cwd.
    if not payload:
        return 0

    source = payload.get(C.FIELD_SOURCE, C.SOURCE_STARTUP)
    if source not in C.INJECT_SOURCES:
        return 0

    cwd = payload.get(C.FIELD_CWD) or str(Path.cwd())
    directory = C.handoff_dir(cwd)
    session_id = payload.get(C.FIELD_SESSION_ID, "")

    context = _handoff_block(directory, session_id)
    # The kaizen nudge rides along with a handoff, or stands alone when learnings
    # are pending but there is no fresh handoff to inject.
    context += _kaizen_nudge(cwd)
    if context.strip():
        _emit(context)
    return 0


def main() -> int:
    try:
        return run(_read_payload())
    except Exception as exc:  # noqa: BLE001 - last-resort guard; never break the session
        # Observability breadcrumb: a genuine raising bug here would otherwise
        # silently kill ALL handoff injections forever with no trace. stderr does
        # NOT block a SessionStart hook, so we keep the never-raise/exit-0
        # guarantee while leaving a diagnosable footprint.
        sys.stderr.write(f"inject_handoff: degraded to no-op after error: {exc}\n")
        return 0


if __name__ == "__main__":
    sys.exit(main())
