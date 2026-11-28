#!/usr/bin/env python3
"""Build or refresh a progress page from a data file.

    build.py --data progress-data.json --out <slug>-progress.html [--title "Name"]

The page's overview (headline, blocker, % to the goal, ordered next steps, stages
step by step, cycles, right-now boxes) is rendered from the JSON by overview-block.html.

- New page: writes a whole document, with an empty "detail" area below the overview.
- Existing page: replaces only what sits between <!-- ov:start --> and <!-- ov:end -->,
  so hand-written detail below the overview survives every refresh. The one thing a
  refresh changes there: every <details> gets the `open` attribute.

It refuses to write when the data has no stage or a stage has no counted step:
a progress bar over nothing would read 0% or 100% without having looked at anything.
"""
import argparse, json, pathlib, re, sys

HERE = pathlib.Path(__file__).resolve().parent
START, END = "<!-- ov:start -->", "<!-- ov:end -->"
STATES = {"done", "doing", "waiting", "todo", "later"}

SHELL = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>
  :root {{ --page-bg:#f6f8f3; --page-ink:#15261d; }}
  @media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{ --page-bg:#111a15; --page-ink:#e9efe9; }} }}
  :root[data-theme="dark"] {{ --page-bg:#111a15; --page-ink:#e9efe9; }}
  body {{ margin:0; background:var(--page-bg); color:var(--page-ink); font:16px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif; }}
  main {{ max-width:1080px; margin:0 auto; padding:24px max(16px, env(safe-area-inset-right)) 64px max(16px, env(safe-area-inset-left)); }}
</style>
</head>
<body>
<main>
{start}
{block}
{end}
<section id="detail">
<!-- Anything below the overview is yours: tables, charts, decisions, caveats. A refresh leaves it alone. -->
</section>
</main>
</body>
</html>
"""


def check(d):
    errs = []
    for k in ("title", "as_of", "headline", "goal", "stages"):
        if not d.get(k):
            errs.append(f"missing '{k}'")
    for st in d.get("stages") or []:
        items = st.get("items") or []
        counted = [i for i in items if i.get("state") != "later"]
        if not counted:
            errs.append(f"stage '{st.get('name')}' has no counted step")
        for i in items:
            if i.get("state") not in STATES:
                errs.append(f"step '{i.get('text')}' has state {i.get('state')!r}; use one of {sorted(STATES)}")
            if not i.get("text"):
                errs.append("a step has no text")
    return errs


MARK = {"done": "[x]", "doing": "[~]", "waiting": "[w]", "todo": "[ ]", "later": "[-]"}
LIST_CAP = {"next_steps": 10, "waiting_on_human": 10, "in_motion": 8, "landed": 8}


def bar(done, total, width=30):
    n = round(width * done / total) if total else 0
    return "[" + "#" * n + "." * (width - n) + f"] {round(100 * done / total) if total else 0}% ({done} of {total})"


def ascii_page(d, width=78):
    """The overview as plain text, from the same data as the HTML, so the two cannot disagree.
    Long lists are cut to LIST_CAP with a '+N more' line; the HTML keeps the full record."""
    import textwrap
    out = []
    def wrap(text, first="", rest=None):
        rest = " " * len(first) if rest is None else rest
        out.extend(textwrap.wrap(str(text), width, initial_indent=first, subsequent_indent=rest) or [first.rstrip()])
    def rule(title):
        out.append("")
        out.append(f"== {title} " + "=" * max(3, width - len(title) - 4))
    def item(i, prefix=None):
        p = prefix if prefix is not None else MARK.get(i.get("state"), "[?]") + " "
        who = f" ({i['owner']})" if i.get("owner") else ""
        wrap(f"{i['text']}{who}", "  " + p)
        pad = " " * (2 + len(p))
        if i.get("note"):
            wrap(i["note"], pad)
        if i.get("url"):
            out.append(pad + i["url"])
    def capped(key, number=False):
        rows = d.get(key) or []
        cap = LIST_CAP[key]
        for n, i in enumerate(rows[:cap], 1):
            item(i, f"{n:>2}. " if number else None)
        if len(rows) > cap:
            out.append(f"  ... +{len(rows) - cap} more on the page")

    out.append("+" + "-" * (width - 2) + "+")
    for line in textwrap.wrap(d["title"], width - 4) or [""]:
        out.append("| " + line.ljust(width - 4) + " |")
    out.append("| " + f"as of {d['as_of']}".ljust(width - 4) + " |")
    out.append("+" + "-" * (width - 2) + "+")
    wrap(d["headline"])
    if d.get("summary"):
        wrap(d["summary"])
    b = d.get("blocker")
    if b:
        rule("BLOCKER")
        wrap(b.get("title", ""), "  ")
        if b.get("text"):
            wrap(b["text"], "  ")
        if b.get("owner"):
            out.append(f"  owner: {b['owner']}")

    counted = [i for s in d["stages"] for i in s["items"] if i["state"] != "later"]
    done = len([i for i in counted if i["state"] == "done"])
    rule("TO THE GOAL")
    out.append("  " + bar(done, len(counted)))
    states = {k: len([i for i in counted if i["state"] == k]) for k in ("done", "doing", "waiting", "todo")}
    out.append("  " + ", ".join(f"{v} {k}" for k, v in states.items()))
    wrap(d["goal"], "  goal: ", "        ")
    if d.get("counts_note"):
        wrap(d["counts_note"], "  ")

    if d.get("next_steps"):
        rule("NEXT STEPS TO 100%")
        capped("next_steps", number=True)

    for s in d["stages"]:
        items = s["items"]
        c = [i for i in items if i["state"] != "later"]
        here = "  <- we are here" if s.get("status") == "current" else ""
        rule(f"{s.get('label') or 'Stage'}: {s.get('name', '')}"[: width - 8])
        out.append("  " + bar(len([i for i in c if i["state"] == "done"]), len(c), 24) + here)
        if s.get("holds"):
            wrap(s["holds"], "  holds: ", "         ")
        for i in items:
            item(i)

    cy = d.get("cycles")
    if cy and cy.get("items"):
        rule(f"CYCLES ({cy.get('source', 'tracker')})")
        for c in cy["items"]:
            out.append(f"  {c['name']}  {c.get('start', '?')} -> {c.get('end', '?')}  " + bar(c.get("done", 0), c.get("total", 0), 16))
            if c.get("url"):
                out.append("    " + c["url"])

    for key, title in (("waiting_on_human", f"WAITING ON {d.get('human_name', 'YOU').upper()}"),
                       ("in_motion", "IN MOTION"), ("landed", "LANDED")):
        if d.get(key):
            rule(f"{title} ({len(d[key])})")
            capped(key)
    out.append("")
    out.append("  [x] done  [~] doing  [w] waiting on someone outside the team")
    out.append("  [ ] to do  [-] later, not counted")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--title")
    ap.add_argument("--no-ascii", action="store_true", help="do not print the plain-text version")
    a = ap.parse_args()

    raw = pathlib.Path(a.data).read_text()
    d = json.loads(raw)
    errs = check(d)
    if errs:
        sys.exit("progress data refused:\n  " + "\n  ".join(errs))

    block = (HERE / "overview-block.html").read_text()
    if "/*DATA*/" not in block:
        sys.exit("overview-block.html has no /*DATA*/ placeholder")
    # "</" inside a JSON string would end the script element early.
    block = block.replace("/*DATA*/", json.dumps(d, ensure_ascii=False, indent=1).replace("</", "<\\/"))

    out = pathlib.Path(a.out)
    if out.exists():
        page = out.read_text()
        if page.count(START) != 1 or page.count(END) != 1:
            sys.exit(f"{out} exists but does not have exactly one {START} / {END} pair; add them around the old overview first")
        i, j = page.index(START), page.index(END)
        page = page[: i + len(START)] + "\n" + block + "\n" + page[j:]
        mode = "refreshed"
    else:
        page = SHELL.format(title=a.title or d["title"], start=START, block=block, end=END)
        mode = "created"
    # Every folded section is expanded by default: a reader should not have to open
    # each line to see the record. The reader can still fold one.
    page, opened = re.subn(r"<details\b(?![^>]*\sopen\b)([^>]*)>", r"<details\1 open>", page)
    out.write_text(page)

    total = sum(len([i for i in s["items"] if i["state"] != "later"]) for s in d["stages"])
    done = sum(len([i for i in s["items"] if i["state"] == "done"]) for s in d["stages"])
    print(f"{mode} {out}: {done} of {total} steps done ({round(100 * done / total)}%), {len(d['stages'])} stages, {opened} folded sections set open")
    if not a.no_ascii:
        text = ascii_page(d)
        txt = out.with_suffix(".txt")
        txt.write_text(text + "\n")
        print(f"ascii version: {txt}\n")
        print(text)


if __name__ == "__main__":
    main()
