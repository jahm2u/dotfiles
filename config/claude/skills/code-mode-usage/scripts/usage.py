#!/usr/bin/env python3
"""Compare real Claude Code sessions run in Code Mode against ordinary ones, over time.

Reads the session transcripts on this Mac, keeps one row per session in a store outside the
repo (transcripts are deleted after about 30 days, the store is not), and prints a comparison.

    usage.py                 scan the last 72 h into the store, print the report
    usage.py --hours 720     scan further back (first run, or after a gap)
    usage.py --log           also append the report to the living log
    usage.py --sessions      list the Code Mode sessions one by one
    usage.py --no-scan       report from the store only

Store and log live in ~/.claude/code-mode-usage/ and hold project names, so they never go in
the (public) dotfiles repo.
"""
import argparse, collections, datetime, glob, json, os, statistics, sys, time

HOME = os.path.expanduser("~")
PROJECTS = os.path.join(HOME, ".claude", "projects")
DATA = os.path.join(HOME, ".claude", "code-mode-usage")
STORE = os.path.join(DATA, "sessions.jsonl")
LOG = os.path.join(DATA, "LOG.md")
DEPTHS = (10, 25, 50, 100, 200)   # context size is compared at the same request number
MIN_REQUESTS = 3

# Synthetic A/B sessions run on 2026-11-17, excluded so that only real work is counted.
SYNTHETIC = {
    "1260f0e2-1fe7-4c3e-829a-24e6e76ea107", "12bebff0-a06b-4256-bf94-1cfde4c9f002",
    "1a3053a3-1f6e-4420-9b88-046eed1fa6f7", "3fafa26e-75e8-4ccd-89fe-e90d82d615d3",
    "56438a62-a32e-4545-8912-7b50d55f8346", "5c54b085-dd7f-48a4-a839-5ef6861d85a6",
    "89f26cb2-2534-417c-9c54-7cd1ee3ab6e7", "d7e2950a-0b40-4e59-bad1-e69caa6c7ac8",
}
CTX_KEYS = ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")


def ts(s):
    return datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def ctx(u):
    return sum(u.get(k, 0) or 0 for k in CTX_KEYS)


def parse(path):
    """One transcript -> one row, or None when it has too few model requests to mean anything."""
    usage = collections.OrderedDict()          # message id -> usage of that model request
    tools, seen = collections.Counter(), set()
    repl, cost, times = None, None, []
    prompts = nested = compacts = 0
    version = entry = cwd = model = None
    for raw in open(path, errors="replace"):
        try:
            e = json.loads(raw)
        except Exception:
            continue
        t = e.get("type")
        if t == "repl-mode":
            repl = e.get("replMode")
        elif t == "cost-state":
            cost = e
        if e.get("isSidechain"):
            continue
        if e.get("timestamp") and t in ("user", "assistant"):
            times.append(ts(e["timestamp"]))
        version = e.get("version") or version
        entry = e.get("entrypoint") or entry
        cwd = e.get("cwd") or cwd
        if t == "system" and e.get("subtype") == "compact_boundary":
            compacts += 1
        if t == "user" and not e.get("isMeta"):
            c = e.get("message", {}).get("content")
            if isinstance(c, str) or (isinstance(c, list) and any(
                    isinstance(b, dict) and b.get("type") == "text" for b in c)):
                prompts += 1
        if t != "assistant":
            continue
        m = e.get("message", {})
        blocks = [b for b in m.get("content", []) if isinstance(b, dict)]
        if e.get("isVirtual"):                 # a tool call made from inside a Code Mode script
            nested += sum(1 for b in blocks if b.get("type") == "tool_use")
            continue
        if m.get("model") and m["model"] != "<synthetic>":
            model = m["model"]
        if m.get("usage"):
            usage[m.get("id")] = m["usage"]
        for b in blocks:
            if b.get("type") == "tool_use" and b["id"] not in seen:
                seen.add(b["id"])
                tools[b["name"]] += 1
    reqs = [u for u in usage.values() if (u.get("output_tokens") or 0) > 0]
    if len(reqs) < MIN_REQUESTS or not times:
        return None
    total = lambda k: sum(u.get(k, 0) or 0 for u in reqs)
    return {
        "sid": os.path.basename(path)[:-6],
        "project": os.path.basename(os.path.dirname(path)),
        "code_mode": bool(repl is True or tools.get("REPL")),
        "model": model, "version": version, "entrypoint": entry,
        "start": min(times), "end": max(times),
        "requests": len(reqs), "prompts": prompts,
        "tool_calls": sum(tools.values()), "nested_tool_calls": nested,
        "first_ctx": ctx(reqs[0]), "peak_ctx": max(ctx(u) for u in reqs),
        "ctx_at": {str(d): ctx(reqs[d - 1]) for d in DEPTHS if len(reqs) >= d},
        "input_total": sum(total(k) for k in CTX_KEYS),
        "cache_write": total("cache_creation_input_tokens"),
        "cache_read": total("cache_read_input_tokens"),
        "output": total("output_tokens"),
        "compactions": compacts,
        "cost_usd": (cost or {}).get("totalCostUSD"),
        "api_seconds": (cost or {}).get("totalAPIDuration", 0) / 1000 if cost else None,
    }


def load_store():
    rows = {}
    if os.path.exists(STORE):
        for line in open(STORE):
            if line.strip():
                r = json.loads(line)
                rows[r["sid"]] = r
    return rows


def scan(hours, rows):
    paths = glob.glob(os.path.join(PROJECTS, "*", "*.jsonl"))
    if not paths:
        sys.exit(f"error: no transcripts under {PROJECTS}; nothing was examined")
    cut = time.time() - hours * 3600
    recent = [p for p in paths if os.path.getmtime(p) >= cut]
    kept = 0
    for p in recent:
        if os.path.basename(p)[:-6] in SYNTHETIC:
            continue
        r = parse(p)
        if r:
            rows[r["sid"]] = r
            kept += 1
    os.makedirs(DATA, exist_ok=True)
    tmp = STORE + ".tmp"
    with open(tmp, "w") as f:
        for r in sorted(rows.values(), key=lambda r: r["start"]):
            f.write(json.dumps(r) + "\n")
    os.replace(tmp, STORE)
    return len(paths), len(recent), kept


def med(xs):
    xs = [x for x in xs if x is not None]
    return statistics.median(xs) if xs else None


def cell(xs, fmt="{:,.0f}"):
    xs = [x for x in xs if x is not None]
    return f"{fmt.format(statistics.median(xs))} ({len(xs)})" if xs else "-"


def report(rows):
    out = []
    rs = list(rows.values())
    on = [r for r in rs if r["code_mode"]]
    first = min(r["start"] for r in rs)
    day = lambda t: datetime.datetime.fromtimestamp(t).strftime("%Y-%m-%d")
    out.append(f"Sessions in the store: {len(rs)} ({day(first)} to {day(max(r['end'] for r in rs))}), "
               f"Code Mode {len(on)}, ordinary {len(rs) - len(on)}.")
    out.append("Each cell is the median, with the number of sessions behind it in brackets.")
    out.append("")
    head = ["model", "mode", "sessions", "start ctx"] + [f"ctx @{d}" for d in DEPTHS] + [
        "out/req", "tools/req", "req/prompt", "$/req", "compactions"]
    out.append("| " + " | ".join(head) + " |")
    out.append("|" + "---|" * len(head))
    models = sorted({r["model"] for r in rs if r["model"]})
    for model in models:
        for mode in (True, False):
            g = [r for r in rs if r["model"] == model and r["code_mode"] == mode]
            if not g:
                continue
            row = [model.replace("claude-", ""), "code" if mode else "ordinary", str(len(g)),
                   cell([r["first_ctx"] for r in g])]
            row += [cell([r["ctx_at"].get(str(d)) for r in g]) for d in DEPTHS]
            row += [
                cell([r["output"] / r["requests"] for r in g]),
                cell([(r["tool_calls"] + r["nested_tool_calls"]) / r["requests"] for r in g], "{:.1f}"),
                cell([r["requests"] / max(r["prompts"], 1) for r in g], "{:.1f}"),
                cell([r["cost_usd"] / r["requests"] if r["cost_usd"] else None for r in g], "{:.3f}"),
                f"{sum(r['compactions'] for r in g)}",
            ]
            out.append("| " + " | ".join(row) + " |")
    out.append("")
    out.append("`ctx @N` is the context size at a session's Nth model request, so sessions of "
               "different length are compared at the same depth. `$/req` is filled only for "
               "sessions that recorded a cost when they ended.")
    return "\n".join(out)


def sessions(rows):
    out = ["| started | project | model | requests | prompts | tools (+nested) | start ctx | peak ctx | output | minutes |",
           "|---|---|---|---|---|---|---|---|---|---|"]
    for r in sorted((r for r in rows.values() if r["code_mode"]), key=lambda r: r["start"]):
        st = datetime.datetime.fromtimestamp(r["start"]).strftime("%m-%d %H:%M")
        out.append(f"| {st} | {r['project'][-30:]} | {(r['model'] or '?').replace('claude-', '')} | {r['requests']} | "
                   f"{r['prompts']} | {r['tool_calls']} (+{r['nested_tool_calls']}) | {r['first_ctx']:,} | "
                   f"{r['peak_ctx']:,} | {r['output']:,} | {(r['end'] - r['start']) / 60:.0f} |")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--hours", type=float, default=72)
    ap.add_argument("--no-scan", action="store_true")
    ap.add_argument("--log", action="store_true")
    ap.add_argument("--sessions", action="store_true")
    a = ap.parse_args()
    rows = load_store()
    if not a.no_scan:
        found, recent, kept = scan(a.hours, rows)
        print(f"Scanned {recent} of {found} transcripts (changed in the last {a.hours:.0f} h); "
              f"{kept} had at least {MIN_REQUESTS} model requests.\n")
    if not rows:
        sys.exit("error: the store is empty; nothing to report")
    text = report(rows)
    print(text)
    if a.sessions:
        print("\nCode Mode sessions:\n\n" + sessions(rows))
    if a.log:
        new = not os.path.exists(LOG)
        with open(LOG, "a") as f:
            if new:
                f.write("# Code Mode usage log\n\nOne entry per check, newest last. Written by "
                        "`usage.py --log`; the notes under each table are added by hand.\n")
            f.write(f"\n## {datetime.datetime.now().strftime('%Y-%m-%d %H:%M')}\n\n{text}\n\n**Notes:**\n")
        print(f"\nAppended to {LOG}")


if __name__ == "__main__":
    main()
