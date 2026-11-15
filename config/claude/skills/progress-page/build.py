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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--title")
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


if __name__ == "__main__":
    main()
