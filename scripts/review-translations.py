#!/usr/bin/env python3
"""Review the EN<->PT translation log to improve the shortcut's prompt.

The translation shortcut (config/hammerspoon/init.lua) logs every translation
to ~/.config/sketchybar/logs/translations.log as JSON lines. This script finds
technical terms that were present in the input but disappeared from the output,
i.e. the model translated jargon it should have preserved in English.

Terms it reports belong in the "RULE 1" list in init.lua.

Usage:
    scripts/review-translations.py              # report leaked jargon
    scripts/review-translations.py --list       # print recent translations
    scripts/review-translations.py --term skill # show cases for one term
"""

import argparse
import json
import os
import re
import sys
from collections import defaultdict

LOG = os.path.expanduser("~/.config/sketchybar/logs/translations.log")

# Jargon that must survive translation. Keep in sync with RULE 1 in init.lua.
TERMS = [
    # AI / product
    "skill", "prompt", "model", "agent", "token", "context", "output",
    # experimentation
    "test", "split", "control", "variant", "arm", "funnel", "lift", "rollout",
    # engineering
    "deploy", "commit", "branch", "merge", "build", "endpoint", "log", "cache",
    # marketing
    "landing page", "checkout", "upsell", "lead", "click", "dashboard",
]


def load(path):
    if not os.path.exists(path):
        sys.exit(f"No translation log yet at {path}\n"
                 "It is written on the first successful translation.")
    records = []
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except json.JSONDecodeError:
            print(f"warning: skipping malformed line {n}", file=sys.stderr)
            continue
        if "input" in r and "output" in r:
            records.append(r)
    return records


def present(term, text):
    """Whole-word match, tolerating a plural 's' and pt-br plural 'es'."""
    return re.search(rf"\b{re.escape(term)}(s|es)?\b", text, re.IGNORECASE) is not None


def report_leaks(records):
    leaks = defaultdict(list)
    for r in records:
        for term in TERMS:
            if present(term, r["input"]) and not present(term, r["output"]):
                leaks[term].append(r)

    if not leaks:
        print(f"No jargon leaks found across {len(records)} translations.")
        return

    print(f"Jargon translated instead of preserved ({len(records)} translations scanned):\n")
    for term, rs in sorted(leaks.items(), key=lambda kv: -len(kv[1])):
        print(f"  {len(rs):3}x  {term:<14} most recent: {rs[-1]['ts']}")
    print("\nAdd recurring terms to the RULE 1 list in config/hammerspoon/init.lua,")
    print("then reload:  open -g hammerspoon://reload")
    print("\nNote: a term can also go missing because the sentence was legitimately")
    print("restructured. Check individual cases with --term before adding.")


def show_term(records, term):
    found = [r for r in records
             if present(term, r["input"]) and not present(term, r["output"])]
    if not found:
        print(f"No cases where '{term}' was dropped from the output.")
        return
    for r in found:
        print(f"--- {r['ts']}  ({r.get('model', 'unknown model')})")
        print(f"IN : {r['input']}")
        print(f"OUT: {r['output']}\n")


def list_all(records, limit):
    for r in records[-limit:]:
        print(f"--- {r['ts']}  ({r.get('model', 'unknown model')})")
        print(f"IN : {r['input']}")
        print(f"OUT: {r['output']}\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--log", default=LOG, help="path to translations.log")
    ap.add_argument("--list", action="store_true", help="print recent translations")
    ap.add_argument("--limit", type=int, default=20, help="how many for --list")
    ap.add_argument("--term", help="show cases where this term was dropped")
    args = ap.parse_args()

    records = load(args.log)

    if args.list:
        list_all(records, args.limit)
    elif args.term:
        show_term(records, args.term)
    else:
        report_leaks(records)


if __name__ == "__main__":
    main()
