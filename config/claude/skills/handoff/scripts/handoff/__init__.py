"""Smart-handoff harness tooling (Claude Code SessionStart/Stop hooks).

Ported from alter-ego AE-0216 (smart handoff). Only the on-disk state root
differs: alter-ego used ``.agent/handoff/``; this module uses ``_bmad/handoff/``
(the single ``_bmad/`` state tree, per the harness-power-up plan §2/D3).
"""
