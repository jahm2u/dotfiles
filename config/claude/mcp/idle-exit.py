#!/usr/bin/python3
"""Run a stdio MCP server, put it to sleep after N minutes without a tool call, and wake it
transparently on the next request.

Usage: idle-exit.py [--idle-minutes N] -- <server command> [args...]
       (MCP_IDLE_MINUTES overrides the default of 30)

Why: chrome-devtools-mcp is in the global MCP list, so every interactive Claude session
starts its own copy and keeps it until the session closes. With 16 sessions open that was
16 node processes, one at 1.15 GB after two idle days, on a Mac whose backups were being
killed for memory (2026-11-12).

Sleeping stops only the server process; this wrapper (~15 MB) stays connected, so Claude never
sees a disconnect and never asks to restart the server. On the next request the server is
started again and the session's original initialize handshake is replayed to it (its reply is
swallowed) before the request goes through. What is lost is server-side state, e.g. which
Chrome tab was selected. Idle means no tools/call for N minutes and no request of any kind
still waiting for its answer, so neither a long call nor a wake-up request is ever cut. Closing the session stops everything.
"""
import json
import os
import signal
import subprocess
import sys
import threading
import time

args = sys.argv[1:]
idle_minutes = float(os.environ.get("MCP_IDLE_MINUTES", "30"))
if args[:1] == ["--idle-minutes"]:
    idle_minutes = float(args[1])
    args = args[2:]
if args[:1] == ["--"]:
    args = args[1:]
if not args:
    sys.exit("usage: idle-exit.py [--idle-minutes N] -- <command> [args...]")

REPLAY_ID = "__idle_exit_replay__"
lock = threading.RLock()
out_lock = threading.Lock()
child = None
init_request = None      # the client's initialize message, replayed on wake
initialized_note = None  # its notifications/initialized
last_call = time.monotonic()
pending = set()
done = threading.Event()
name = os.path.basename(args[0])


def log(msg):
    sys.stderr.write("[idle-exit] %s\n" % msg)
    sys.stderr.flush()


def parse(line):
    try:
        obj = json.loads(line)
    except ValueError:
        return []
    return [m for m in (obj if isinstance(obj, list) else [obj]) if isinstance(m, dict)]


def pump(proc):
    """Copy one server process's output to the client, dropping replies to replayed messages."""
    for line in proc.stdout:
        msgs = parse(line)
        if msgs and all(m.get("id") == REPLAY_ID for m in msgs):
            continue
        for m in msgs:
            if "id" in m and "method" not in m:
                with lock:
                    key = json.dumps(m.get("id"))
                    if key in pending:
                        pending.discard(key)
                        globals()["last_call"] = time.monotonic()
        with out_lock:
            try:
                sys.stdout.buffer.write(line)
                sys.stdout.buffer.flush()
            except BrokenPipeError:
                done.set()
                return
    with lock:
        if proc is child:  # died on its own, not put to sleep: same as before the wrapper
            log("%s exited (rc=%s)" % (name, proc.poll()))
            done.set()


def write(proc, data):
    proc.stdin.write(data)
    proc.stdin.flush()


def start(replay):
    global child
    proc = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    child = proc
    threading.Thread(target=pump, args=(proc,), daemon=True).start()
    if replay and init_request is not None:
        m = dict(init_request, id=REPLAY_ID)
        write(proc, (json.dumps(m) + "\n").encode())
        if initialized_note is not None:
            write(proc, initialized_note)
        log("woke %s and replayed initialize" % name)
    return proc


def sleep_child():
    global child
    proc, child = child, None
    if proc and proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(5)
        except subprocess.TimeoutExpired:
            proc.kill()


def client_to_server():
    global init_request, initialized_note, last_call
    for line in sys.stdin.buffer:
        msgs = parse(line)
        with lock:
            for m in msgs:
                if m.get("method") == "initialize":
                    init_request = m
                elif m.get("method") == "notifications/initialized":
                    initialized_note = line
                elif m.get("method") == "tools/call":
                    last_call = time.monotonic()
                if "id" in m and "method" in m:  # any request: never sleep before it is answered
                    pending.add(json.dumps(m.get("id")))
            if child is None:
                last_call = time.monotonic()  # a fresh wake gets a full idle period
            proc = child or start(replay=True)
            try:
                write(proc, line)
            except (BrokenPipeError, ValueError):
                break
    done.set()  # the session closed its end: stop the server too


for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
    signal.signal(sig, lambda *_: done.set())

start(replay=False)
threading.Thread(target=client_to_server, daemon=True).start()

limit = idle_minutes * 60
while not done.wait(min(30.0, max(limit / 4, 0.5))):
    with lock:
        if child is not None and not pending and time.monotonic() - last_call >= limit:
            log("no tool call for %.1f min: %s sleeps until the next request" % (limit / 60, name))
            sleep_child()

with lock:
    sleep_child()
sys.stdout.flush()
os._exit(0)  # a reader thread may still block on stdin; a normal exit would abort on it
