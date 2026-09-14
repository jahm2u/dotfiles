#!/usr/bin/env python3
"""Replay translation inputs through the prompt in config/hammerspoon/init.lua.

Judges a prompt change on real model output instead of by eye. The prompt, system
message and temperature are extracted from init.lua itself (the artifact that runs),
never re-typed here. `--old` also runs the committed version (git HEAD) for
comparison; `--model` adds extra models.

    scripts/replay-translations.py --old "is your account a paid account?"
    scripts/replay-translations.py --model gpt-4.1-nano < cases.txt   # one case per line
"""
import argparse, json, os, re, subprocess, sys, urllib.request
import concurrent.futures as cf

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INIT = os.path.join(REPO, "config", "hammerspoon", "init.lua")


def api_key():
    for line in open(os.path.join(REPO, ".env"), encoding="utf-8"):
        if line.startswith("OPENAI_API_KEY"):
            return line.split("=", 1)[1].strip().strip('"')
    sys.exit("OPENAI_API_KEY not found in .env")


def detect_target(text):
    """Run the REAL detector from init.lua through Hammerspoon, never a Python copy."""
    tmp = os.path.join(os.environ.get("TMPDIR", "/tmp"), "replay-translations-input.txt")
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    out = subprocess.run(["/opt/homebrew/bin/hs", "-c",
                          'print("TARGET=" .. tostring(detectTranslationTarget(io.open("%s"):read("a"))))' % tmp],
                         capture_output=True, text=True, timeout=30).stdout
    m = re.search(r"TARGET=(\S+)", out)
    if not m:
        sys.exit("could not run detectTranslationTarget via hs (is Hammerspoon running with the current init.lua?)")
    return None if m.group(1) == "nil" else m.group(1)


def direction_line(target):
    if target:
        source = "Portuguese" if target == "English" else "English"
        return ("The text is in %s. Translate it into %s.\n"
                "Do not re-decide the direction: English jargon inside a Portuguese sentence does not make it English.\n"
                "Sentences already entirely in %s are copied through unchanged; everything else is translated.\n"
                "Returning the text unchanged is never a valid answer.\n" % (source, target, target))
    return ("- If it's in English → translate to Portuguese\n"
            "- If it's in Portuguese → translate to English\n"
            "- If it mixes both, pick ONE target language for the whole text: the language\n"
            "  most of the text is in is the source. Translate those parts and copy the parts\n"
            "  already in the target language through unchanged. Never translate in both\n"
            "  directions within one text\n")


def extract(source):
    m = re.search(r'local prompt = \[\[\n(.*?)\]\] \.\. directionLine \.\. \[\[\n(.*?)\]\] \.\. text \.\. \[\[(\n?)(.*?)\]\]', source, re.S)
    dynamic = m is not None
    if not m:
        m = re.search(r'local prompt = \[\[\n(.*?)()\]\] \.\. text(?::gsub\([^)]*\))? \.\. \[\[(\n?)(.*?)\]\]', source, re.S)
    if not m:
        sys.exit("could not find the prompt template in init.lua")
    escapes_quotes = ":gsub" in m.group(0)
    sysmsg = re.search(r'\{role = "system", content = "(.*?)"\}', source).group(1)
    model = re.search(r'local TRANSLATE_MODEL = "([^"]+)"', source).group(1)
    temp = re.search(r'temperature = ([\d.]+)', source)
    return dict(head=m.group(1), mid=m.group(2), tail=m.group(4), dynamic=dynamic, escapes_quotes=escapes_quotes,
                sysmsg=sysmsg, model=model, temperature=float(temp.group(1)) if temp else None)


def call(key, cfg, model, text):
    if cfg["escapes_quotes"]:
        text = text.replace('"', '\\"')
    if cfg["dynamic"]:
        user = cfg["head"] + direction_line(detect_target(text)) + cfg["mid"] + text + cfg["tail"]
    else:
        user = cfg["head"] + text + cfg["tail"]
    body = {"model": model,
            "messages": [{"role": "system", "content": cfg["sysmsg"]},
                         {"role": "user", "content": user}],
            "safety_identifier": "dotfiles-translate"}
    if cfg["temperature"] is not None:
        body["temperature"] = cfg["temperature"]
    req = urllib.request.Request("https://api.openai.com/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
    return json.load(urllib.request.urlopen(req, timeout=90))["choices"][0]["message"]["content"]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cases", nargs="*", help="texts to translate (default: stdin, one per line)")
    ap.add_argument("--old", action="store_true", help="also run the prompt committed at git HEAD")
    ap.add_argument("--model", action="append", default=[], help="extra model(s) to run the current prompt on")
    args = ap.parse_args()
    cases = args.cases or [l.rstrip("\n") for l in sys.stdin if l.strip()]
    if not cases:
        sys.exit("no cases given")

    key = api_key()
    new = extract(open(INIT, encoding="utf-8").read())
    runs = [("NEW/" + new["model"], new, new["model"])]
    for m in args.model:
        runs.append(("NEW/" + m, new, m))
    if args.old:
        old = extract(subprocess.check_output(["git", "-C", REPO, "show", "HEAD:config/hammerspoon/init.lua"], text=True))
        runs.insert(0, ("OLD/" + old["model"], old, old["model"]))

    jobs = [(label, cfg, model, i, t) for label, cfg, model in runs for i, t in enumerate(cases)]
    with cf.ThreadPoolExecutor(12) as ex:
        outs = list(ex.map(lambda j: call(key, j[1], j[2], j[4]), jobs))
    res = {(j[0], j[3]): o for j, o in zip(jobs, outs)}
    width = max(len(r[0]) for r in runs)
    for i, t in enumerate(cases):
        print("\n#### IN :", t.replace("\n", " | "))
        for label, _, _ in runs:
            print(f"{label:{width}}: {res[(label, i)]}".replace("\n", " | "))


if __name__ == "__main__":
    main()
