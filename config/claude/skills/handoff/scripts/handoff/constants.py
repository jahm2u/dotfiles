"""Shared constants for the smart-handoff harness tooling.

Ported from alter-ego AE-0216 (smart handoff) with VERBATIM logic. The ONLY
adaptation is the state root: ``HANDOFF_DIR_NAME`` moves from ``.agent/handoff``
to ``_bmad/handoff`` (the single ``_bmad/`` state tree; harness-power-up §2/D3).
Every other constant — the injection cap, inject sources, usage fields, and the
reminder threshold/step — is preserved unchanged.

These scripts run as Claude Code hooks (SessionStart injection + an optional
non-blocking Stop reminder). They are stdlib-only and never raise into the
harness: any failure must degrade to a no-op so a broken handoff never blocks a
session from starting or a turn from completing. They also no-op cleanly when
``_bmad/handoff/`` is absent — the hooks are installed globally and run on EVERY
project's session start, including non-harness projects.
"""

from __future__ import annotations

import json
import os
import tempfile
from contextlib import contextmanager
from pathlib import Path

try:  # pragma: no cover - absent only on non-POSIX platforms
    import fcntl
except ImportError:  # pragma: no cover
    fcntl = None  # type: ignore[assignment]

# --- Filesystem layout (relative to the repo / cwd the hook runs in) ----------
# AE-0216 used ".agent/handoff"; ipmedia-skills uses the single "_bmad/" tree.
HANDOFF_DIR_NAME = "_bmad/handoff"
HANDOFF_MARKDOWN_NAME = "HANDOFF-latest.md"
HANDOFF_JSON_NAME = "HANDOFF-latest.json"
CONSUMED_FILE_NAME = ".consumed"
REMINDER_STATE_FILE_NAME = ".reminder"
# Sidecar appended to a state file's name to get its advisory-lock file.
LOCK_SUFFIX = ".lock"
# Append-only kaizen signal: one distilled learnings record per handoff.
LEARNINGS_LOG_NAME = "learnings-log.jsonl"
# Watermark: `created_at` of the newest learnings record kaizen has processed.
KAIZEN_WATERMARK_NAME = ".kaizen-watermark"

# --- SessionStart `source` values (Claude Code hooks contract) ----------------
SOURCE_STARTUP = "startup"
SOURCE_RESUME = "resume"
SOURCE_CLEAR = "clear"
SOURCE_COMPACT = "compact"
# We inject on every source EXCEPT compact: compaction keeps the SAME session,
# which already holds the (about-to-be-summarised) context, so re-injecting the
# handoff there is redundant and risks a self-injection loop.
INJECT_SOURCES = frozenset({SOURCE_STARTUP, SOURCE_RESUME, SOURCE_CLEAR})

# --- Hook output contract (verbatim field names from the hooks docs) ----------
HOOK_OUTPUT_KEY = "hookSpecificOutput"
HOOK_EVENT_NAME_KEY = "hookEventName"
ADDITIONAL_CONTEXT_KEY = "additionalContext"
SESSION_START_EVENT = "SessionStart"
STOP_EVENT = "Stop"

# --- Stdin field names --------------------------------------------------------
FIELD_SOURCE = "source"
FIELD_SESSION_ID = "session_id"
FIELD_CWD = "cwd"
FIELD_TRANSCRIPT_PATH = "transcript_path"

# --- Context-window accounting (mirrors the statusline token accounting) ------
# Total window in tokens. This is CONFIGURATION, not detection: the transcript
# records the model as e.g. "claude-opus-5" with no variant marker, so a 1M build
# is indistinguishable from a 200k one at runtime (verified against a live 1M
# session — every record read `claude-opus-5`).
#
# The default is 1M because that is what this org actually runs. The previous
# 200_000 was a verbatim port from AE-0216, correct for the model of its day and
# silently wrong here: on a 1M build it made the Stop reminder fire at ~14% real
# utilisation, which in one long session produced seven false alarms reporting
# "75% full" through "310% full". Alarm fatigue is a real failure mode — a nudge
# nobody believes is worth less than no nudge.
#
# KNOWN TRADE-OFF, stated rather than hidden: on a 200k model this default makes
# the reminder fire late or never, and hitting auto-compact unwarned is the more
# damaging direction. Anyone on a 200k build must set the window explicitly —
# that is what the `contextWindow` plugin option exists for, and why it is
# prompted at enable time rather than buried in a config file.
#
# Two sources, highest first:
#   1. HANDOFF_CONTEXT_WINDOW              — explicit env override
#   2. CLAUDE_PLUGIN_OPTION_CONTEXTWINDOW  — the plugin `userConfig` value, which
#      Claude Code exports to hook processes as CLAUDE_PLUGIN_OPTION_<KEY>.
#      (Shell-form hook commands reject ${user_config.*} interpolation, so the
#      environment is the prescribed way to read it.)
DEFAULT_CONTEXT_WINDOW = 1_000_000
CONTEXT_WINDOW_ENV = "HANDOFF_CONTEXT_WINDOW"
CONTEXT_WINDOW_PLUGIN_ENV = "CLAUDE_PLUGIN_OPTION_CONTEXTWINDOW"

# Stop-hook reminder fires at/above this fraction of the window, then again each
# time utilisation climbs another REMINDER_STEP. Tunable via env.
DEFAULT_REMINDER_THRESHOLD = 0.70
REMINDER_THRESHOLD_ENV = "HANDOFF_REMINDER_THRESHOLD"
REMINDER_STEP = 0.10

# usage sub-fields summed to approximate live context utilisation
USAGE_FIELDS = (
    "input_tokens",
    "cache_creation_input_tokens",
    "cache_read_input_tokens",
    "output_tokens",
)

# Practical ceiling for injected context. additionalContext has no documented
# hard limit, but a multi-hundred-KB blob is wasteful and may not be attended to;
# truncate with a pointer to the on-disk file instead.
MAX_INJECT_CHARS = 24_000


def handoff_dir(cwd: str) -> Path:
    """Return the handoff directory for a given working directory."""
    return Path(cwd) / HANDOFF_DIR_NAME


@contextmanager
def exclusive_lock(target: Path):
    """Serialise a read-modify-write on `target` across processes.

    Two Claude Code sessions can hit the same `_bmad/handoff/` state at once —
    concurrent `SessionStart` hooks racing on `.consumed`, or a handoff write
    racing a learnings append. Each writer holds an exclusive `flock` on a
    sidecar `<name>.lock` for the whole read-check-write, so the loser waits
    instead of clobbering.

    Degrades to a no-op (rather than raising) wherever locking is unavailable:
    the hooks must never break a session over a missing lock primitive.
    """
    handle = None
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        handle = open(target.with_name(target.name + LOCK_SUFFIX), "a+")
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
    except (OSError, AttributeError, NameError):
        if handle is not None:
            handle.close()
            handle = None
    try:
        yield
    finally:
        if handle is not None:
            try:
                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
            except OSError:
                pass
            handle.close()


def atomic_write_text(target: Path, text: str) -> None:
    """Publish `text` at `target` by rename, so readers never see a partial file.

    Raises OSError like a plain write would; callers decide whether that is
    fatal or best-effort.
    """
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp_fd, tmp_name = tempfile.mkstemp(dir=str(target.parent), prefix=target.name + ".", suffix=".tmp")
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.replace(tmp_name, target)
    except BaseException:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise


def context_window() -> int:
    """Resolved context-window size in tokens.

    Precedence: HANDOFF_CONTEXT_WINDOW, then the plugin `userConfig` value
    exported as CLAUDE_PLUGIN_OPTION_CONTEXTWINDOW, then the conservative default.
    Never raises: a malformed value in either source falls through to the next.
    """
    for name in (CONTEXT_WINDOW_ENV, CONTEXT_WINDOW_PLUGIN_ENV):
        raw = os.environ.get(name, "").strip()
        if not raw:
            continue
        # userConfig `number` values may arrive as "1000000" or "1000000.0".
        # int(float(...)) must also survive "inf"/"nan": float() accepts both and
        # int() then raises OverflowError/ValueError, which would propagate out of
        # a hook that is contractually never allowed to raise.
        try:
            parsed = float(raw)
            if parsed != parsed or parsed in (float("inf"), float("-inf")):
                continue
            value = int(parsed)
        except (ValueError, OverflowError):
            continue
        if value > 0:
            return value
    return DEFAULT_CONTEXT_WINDOW


def reminder_threshold() -> float:
    """Resolved reminder threshold fraction (env override or default)."""
    raw = os.environ.get(REMINDER_THRESHOLD_ENV, "")
    try:
        value = float(raw)
    except ValueError:
        return DEFAULT_REMINDER_THRESHOLD
    if 0.0 < value < 1.0:
        return value
    return DEFAULT_REMINDER_THRESHOLD


def pending_learnings_count(cwd: str) -> int:
    """Count learnings records newer than the kaizen watermark (0 on any error).

    Used to nudge a fresh session to run the learnings review. A record is
    "pending" if its `created_at` sorts after the watermark; with no watermark,
    every record is pending. Never raises — returns 0 on missing/garbled files.
    """
    directory = handoff_dir(cwd)
    log_path = directory / LEARNINGS_LOG_NAME
    if not log_path.is_file():
        return 0
    try:
        lines = [ln for ln in log_path.read_text(encoding="utf-8").splitlines() if ln.strip()]
    except (OSError, UnicodeDecodeError):
        return 0

    watermark = ""
    watermark_path = directory / KAIZEN_WATERMARK_NAME
    if watermark_path.is_file():
        try:
            watermark = watermark_path.read_text(encoding="utf-8").strip()
        except (OSError, UnicodeDecodeError):
            watermark = ""

    pending = 0
    for line in lines:
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        # A syntactically valid line may still be a list/string/number; .get()
        # on those raises AttributeError and would break the never-raise contract.
        if not isinstance(record, dict):
            continue
        created_at = str(record.get("created_at", ""))
        if not watermark or created_at > watermark:
            pending += 1
    return pending
