#!/usr/bin/env python3
"""Tests for the decisions-guard hook in log_learnings.run().

Run: python3 -m unittest config/claude/skills/handoff/scripts/handoff/test_log_learnings.py
(from the dotfiles root, or any cwd: the module path is inserted below).
"""

from __future__ import annotations

import io
import json
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from scripts.handoff import log_learnings as L  # noqa: E402

HAS_NODE = shutil.which("node") is not None

HANDOFF = {
    "created_at": "2026-11-24T15:00:00Z",
    "mission": "test",
    "decisions": [{"decision": "Jeff, 2026-11-24: x", "rationale": "y"}],
}


def _root(guard_body: str | None) -> Path:
    root = Path(tempfile.mkdtemp())
    handoff_dir = root / "_bmad" / "handoff"
    handoff_dir.mkdir(parents=True)
    (handoff_dir / "HANDOFF-latest.json").write_text(json.dumps(HANDOFF), encoding="utf-8")
    if guard_body is not None:
        (root / "scripts").mkdir()
        (root / L.DECISIONS_GUARD).write_text(guard_body, encoding="utf-8")
    return root


def _run(root: Path) -> tuple[int, str, int]:
    err = io.StringIO()
    with redirect_stderr(err):
        code = L.run(str(root))
    log = root / "_bmad" / "handoff" / "learnings-log.jsonl"
    lines = len(log.read_text(encoding="utf-8").splitlines()) if log.exists() else 0
    return code, err.getvalue(), lines


@unittest.skipUnless(HAS_NODE, "node not on PATH")
class DecisionsGuardTest(unittest.TestCase):
    def test_no_script_appends(self):
        code, _, lines = _run(_root(None))
        self.assertEqual((code, lines), (0, 1))

    def test_exit_0_appends(self):
        code, _, lines = _run(_root("process.exit(0)\n"))
        self.assertEqual((code, lines), (0, 1))

    def test_exit_1_refuses_and_prints_missing(self):
        body = "console.log('missing: https://github.com/jahm2u/BabaFlow/issues/1 x'); process.exit(1)\n"
        code, err, lines = _run(_root(body))
        self.assertEqual((code, lines), (1, 0))
        self.assertIn("missing: https://github.com/jahm2u/BabaFlow/issues/1 x", err)
        self.assertIn("refused:", err)

    def test_exit_2_warns_and_appends(self):
        code, err, lines = _run(_root("console.error('gh read failed'); process.exit(2)\n"))
        self.assertEqual((code, lines), (0, 1))
        self.assertIn("exited 2: gh read failed", err)

    def test_timeout_warns_and_appends(self):
        with mock.patch.object(L, "GUARD_TIMEOUT_S", 1):
            code, err, lines = _run(_root("setTimeout(() => {}, 10000)\n"))
        self.assertEqual((code, lines), (0, 1))
        self.assertIn("timed out", err)

    def test_guard_receives_repo_root(self):
        root = _root("process.exit(process.argv[2] === process.env.WANT ? 0 : 1)\n")
        with mock.patch.dict("os.environ", {"WANT": str(root)}):
            code, _, lines = _run(root)
        self.assertEqual((code, lines), (0, 1))


class NoNodeTest(unittest.TestCase):
    def test_missing_node_warns_and_appends(self):
        root = _root("process.exit(1)\n")
        with mock.patch.object(L.subprocess, "run", side_effect=FileNotFoundError("node")):
            code, err, lines = _run(root)
        self.assertEqual((code, lines), (0, 1))
        self.assertIn("could not run", err)


if __name__ == "__main__":
    unittest.main()
