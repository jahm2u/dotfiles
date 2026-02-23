#!/usr/bin/env python3
"""Mac Mini MQTT Monitor — publishes system metrics to Home Assistant via MQTT auto-discovery."""

from __future__ import annotations  # PEP 604 union types (X | Y) on Python 3.9

import argparse
import json
import logging
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import ctypes
import ctypes.util

import psutil
import paho.mqtt.client as mqtt
from paho.mqtt.enums import CallbackAPIVersion

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
logger = logging.getLogger("mac-monitor")
running = True
_mqtt_client: mqtt.Client | None = None
_cfg: dict | None = None


def _console_uid() -> str | None:
    """Get the UID of the currently logged-in console user.

    /dev/console is owned by the GUI user on macOS.
    Returns UID as string, or None if nobody is logged in.
    """
    try:
        result = subprocess.run(
            ["stat", "-f", "%u", "/dev/console"],
            capture_output=True, text=True, timeout=5,
        )
        uid = result.stdout.strip()
        return uid if uid and uid != "0" else None
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None


def _run_as_user(cmd: list[str], **kwargs) -> subprocess.CompletedProcess | None:
    """Run a command in the console user's GUI session via launchctl asuser.

    Falls back to running directly if no console user (e.g. nobody logged in).
    """
    uid = _console_uid()
    if uid:
        full_cmd = ["launchctl", "asuser", uid] + cmd
    else:
        full_cmd = cmd
    try:
        return subprocess.run(full_cmd, capture_output=True, text=True, timeout=10, **kwargs)
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        logger.warning("_run_as_user failed: %s (cmd=%s)", e, cmd)
        return None


def _popen_as_user(cmd: list[str]) -> subprocess.Popen | None:
    """Popen variant for fire-and-forget commands in user session."""
    uid = _console_uid()
    if uid:
        full_cmd = ["launchctl", "asuser", uid] + cmd
    else:
        full_cmd = cmd
    try:
        return subprocess.Popen(full_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError as e:
        logger.warning("_popen_as_user failed: %s (cmd=%s)", e, cmd)
        return None


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
def load_config(path: str) -> dict:
    with open(path) as f:
        cfg = json.load(f)
    # Validate required fields
    for key in ("node_id", "device_name", "mqtt"):
        if key not in cfg:
            raise ValueError(f"Missing required config key: {key}")
    for key in ("host", "port", "username", "password"):
        if key not in cfg["mqtt"]:
            raise ValueError(f"Missing required mqtt config key: {key}")
    cfg.setdefault("publish_interval", 30)
    cfg.setdefault("drives", [{"name": "root", "path": "/", "label": "Internal SSD"}])
    cfg.setdefault("controls", {})
    cfg.setdefault("cpu_temp_enabled", False)
    cfg.setdefault("docker", {"enabled": False, "watched_containers": []})
    cfg.setdefault("shortcuts", [])
    cfg.setdefault("mac_address", "")
    cfg.setdefault("device_model", "Mac mini")
    return cfg


# ---------------------------------------------------------------------------
# Sensor collectors
# ---------------------------------------------------------------------------
def collect_cpu() -> dict:
    # interval=None returns average since last call (~30s rolling window).
    # Avoids the 1-second blocking snapshot that over-reports vs Activity Monitor.
    return {"cpu_percent": psutil.cpu_percent(interval=None)}


def collect_memory() -> dict:
    mem = psutil.virtual_memory()
    # macOS: psutil.percent counts inactive/cached as used (inflated).
    # Use active + wired for Activity Monitor-like "App Memory" value.
    real_used = mem.active + mem.wired
    real_pct = round(real_used / mem.total * 100, 1) if mem.total else 0.0
    return {
        "ram_percent": real_pct,
        "ram_used_gb": round(real_used / (1024**3), 1),
        "ram_total_gb": round(mem.total / (1024**3), 1),
    }


def collect_load() -> dict:
    load1, load5, load15 = os.getloadavg()
    return {
        "load_1m": round(load1, 2),
        "load_5m": round(load5, 2),
        "load_15m": round(load15, 2),
    }


def collect_disks(drives: list[dict]) -> dict:
    data = {}
    for drv in drives:
        name = drv["name"]
        path = drv["path"]
        is_root = path == "/"
        # macOS APFS: "/" is a sealed snapshot (~4%). Use /System/Volumes/Data
        # for real usage, which shares the APFS container with the system volume.
        if is_root:
            data_vol = "/System/Volumes/Data"
            if os.path.isdir(data_vol):
                path = data_vol
        # Root/Data volume is always available; ismount() returns False for
        # /System/Volumes/Data on APFS, so skip the check for root drives.
        mounted = True if is_root else os.path.ismount(path)
        data[f"drive_{name}_connected"] = mounted
        if mounted:
            try:
                usage = psutil.disk_usage(path)
                data[f"disk_{name}_percent"] = round(usage.percent, 1)
            except OSError:
                data[f"disk_{name}_percent"] = None
        else:
            data[f"disk_{name}_percent"] = None
    return data


def collect_network() -> dict:
    counters = psutil.net_io_counters()
    return {
        "net_sent_gb": round(counters.bytes_sent / (1024**3), 2),
        "net_recv_gb": round(counters.bytes_recv / (1024**3), 2),
    }


def collect_uptime() -> dict:
    boot = psutil.boot_time()
    uptime_secs = time.time() - boot
    return {"uptime_days": round(uptime_secs / 86400, 2)}


def collect_cpu_temp() -> dict | None:
    """Read CPU temperature via powermetrics (requires sudoers NOPASSWD entry)."""
    try:
        result = subprocess.run(
            ["powermetrics", "--samplers", "smc", "-n", "1", "-i", "100"],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode != 0:
            return None
        for line in result.stdout.splitlines():
            if "CPU die temperature" in line:
                temp_str = line.split(":")[1].strip().replace(" C", "").replace("°", "")
                return {"cpu_temp": round(float(temp_str), 1)}
    except (subprocess.TimeoutExpired, FileNotFoundError, ValueError, IndexError):
        pass
    return None


def collect_idle_time() -> dict:
    """Get user idle time from IOKit HIDIdleTime (nanoseconds -> minutes)."""
    try:
        result = subprocess.run(
            ["ioreg", "-c", "IOHIDSystem", "-d", "4"],
            capture_output=True, text=True, timeout=5,
        )
        for line in result.stdout.splitlines():
            if "HIDIdleTime" in line and "=" in line:
                # Format: "HIDIdleTime" = 1234567890
                val = line.split("=")[-1].strip()
                ns = int(val)
                minutes = round(ns / 1_000_000_000 / 60, 1)
                return {"user_idle_minutes": minutes}
    except (subprocess.TimeoutExpired, FileNotFoundError, ValueError):
        pass
    return {"user_idle_minutes": 0}


def collect_display_sleep() -> dict:
    """Check if display is asleep via IODisplayWrangler CurrentPowerState."""
    try:
        result = subprocess.run(
            ["ioreg", "-n", "IODisplayWrangler", "-d", "2"],
            capture_output=True, text=True, timeout=5,
        )
        for line in result.stdout.splitlines():
            if "CurrentPowerState" in line and "=" in line:
                val = int(line.split("=")[-1].strip())
                return {"display_asleep": val < 4}
    except (subprocess.TimeoutExpired, FileNotFoundError, ValueError):
        pass
    return {"display_asleep": False}


def _get_coreaudio():
    """Load CoreAudio framework and return (lib, Addr class, default_input_device_id)."""
    ca = ctypes.cdll.LoadLibrary("/System/Library/Frameworks/CoreAudio.framework/CoreAudio")

    class Addr(ctypes.Structure):
        _fields_ = [("sel", ctypes.c_uint32), ("scope", ctypes.c_uint32), ("elem", ctypes.c_uint32)]

    glob = int.from_bytes(b"glob", "big")
    addr = Addr(int.from_bytes(b"dIn ", "big"), glob, 0)
    dev_id = ctypes.c_uint32(0)
    sz = ctypes.c_uint32(4)
    if ca.AudioObjectGetPropertyData(1, ctypes.byref(addr), 0, None, ctypes.byref(sz), ctypes.byref(dev_id)) != 0:
        return None, None, None
    return ca, Addr, dev_id.value


def _get_coreaudio_output():
    """Load CoreAudio and find output volume targets.

    Returns (ca_lib, Addr_class, targets) where targets is a list of
    (device_id, volume_channel) tuples for setting output volume.

    For aggregate devices (LG Dual), enumerates all devices and finds
    individual LG display outputs that support volume control.
    For regular devices, targets is just the default output.
    """
    ca = ctypes.cdll.LoadLibrary("/System/Library/Frameworks/CoreAudio.framework/CoreAudio")
    cf = ctypes.cdll.LoadLibrary("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
    cf.CFStringGetCStringPtr.restype = ctypes.c_char_p
    cf.CFStringGetCStringPtr.argtypes = [ctypes.c_void_p, ctypes.c_uint32]

    class Addr(ctypes.Structure):
        _fields_ = [("sel", ctypes.c_uint32), ("scope", ctypes.c_uint32), ("elem", ctypes.c_uint32)]

    def S(s):
        return int.from_bytes(s.encode() if isinstance(s, str) else s, "big")

    def has_out_vol(did):
        for ch in (0, 1):
            a = Addr(S("volm"), S("outp"), ch)
            v = ctypes.c_float(0.0)
            s = ctypes.c_uint32(4)
            if ca.AudioObjectGetPropertyData(did, ctypes.byref(a), 0, None, ctypes.byref(s), ctypes.byref(v)) == 0:
                return ch
        return -1

    def get_name(did):
        addr = Addr(S("lnam"), S("glob"), 0)
        name_ref = ctypes.c_void_p(0)
        sz = ctypes.c_uint32(8)
        if ca.AudioObjectGetPropertyData(did, ctypes.byref(addr), 0, None, ctypes.byref(sz), ctypes.byref(name_ref)) == 0:
            cstr = cf.CFStringGetCStringPtr(name_ref, 0x08000100)
            if cstr:
                return cstr.decode()
            # Fallback: CFStringGetCString
            buf = ctypes.create_string_buffer(256)
            if cf.CFStringGetCString(name_ref, buf, 256, 0x08000100):
                return buf.value.decode()
        return ""

    # Get default output device
    addr = Addr(S("dOut"), S("glob"), 0)
    dev_id = ctypes.c_uint32(0)
    sz = ctypes.c_uint32(4)
    if ca.AudioObjectGetPropertyData(1, ctypes.byref(addr), 0, None, ctypes.byref(sz), ctypes.byref(dev_id)) != 0:
        return None, None, []

    # Try default device directly
    ch = has_out_vol(dev_id.value)
    if ch >= 0:
        return ca, Addr, [(dev_id.value, ch)]

    # Aggregate/multi-output — enumerate all devices, find LG outputs with volume
    addr = Addr(S("dev#"), S("glob"), 0)
    sz = ctypes.c_uint32(0)
    ca.AudioObjectGetPropertyDataSize(1, ctypes.byref(addr), 0, None, ctypes.byref(sz))
    n = sz.value // 4
    if n == 0:
        return None, None, []
    all_ids = (ctypes.c_uint32 * n)()
    sz2 = ctypes.c_uint32(n * 4)
    ca.AudioObjectGetPropertyData(1, ctypes.byref(addr), 0, None, ctypes.byref(sz2), all_ids)

    targets = []
    for did in all_ids:
        if did == dev_id.value:
            continue
        ch = has_out_vol(did)
        if ch < 0:
            continue
        name = get_name(did)
        if "LG" in name:
            targets.append((did, ch))

    return (ca, Addr, targets) if targets else (None, None, [])


def collect_mic() -> dict:
    """Get mic volume and mute state via CoreAudio HAL (works with USB/display mics)."""
    try:
        ca, Addr, dev = _get_coreaudio()
        if ca is None:
            return {"mic_muted": False, "mic_volume": 0}
        inp = int.from_bytes(b"inpt", "big")
        volm = int.from_bytes(b"volm", "big")
        addr = Addr(volm, inp, 1)  # channel 1
        vol = ctypes.c_float(0.0)
        sz = ctypes.c_uint32(4)
        if ca.AudioObjectGetPropertyData(dev, ctypes.byref(addr), 0, None, ctypes.byref(sz), ctypes.byref(vol)) != 0:
            return {"mic_muted": False, "mic_volume": 0}
        pct = round(vol.value * 100)
        return {"mic_muted": pct == 0, "mic_volume": pct}
    except Exception:
        return {"mic_muted": False, "mic_volume": 0}


def collect_mic_in_use() -> dict:
    """Check if any app is actively using the microphone via CoreAudio HAL."""
    try:
        ca, Addr, dev = _get_coreaudio()
        if ca is None:
            return {"mic_in_use": False}
        glob = int.from_bytes(b"glob", "big")
        addr = Addr(int.from_bytes(b"goin", "big"), glob, 0)
        running_flag = ctypes.c_uint32(0)
        sz = ctypes.c_uint32(4)
        if ca.AudioObjectGetPropertyData(dev, ctypes.byref(addr), 0, None, ctypes.byref(sz), ctypes.byref(running_flag)) != 0:
            return {"mic_in_use": False}
        return {"mic_in_use": bool(running_flag.value)}
    except Exception:
        return {"mic_in_use": False}


def _find_tool(name: str) -> str | None:
    """Find a CLI tool, checking Homebrew paths that root can't see via PATH."""
    found = shutil.which(name)
    if found:
        return found
    for prefix in ["/opt/homebrew/bin", "/usr/local/bin"]:
        path = os.path.join(prefix, name)
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    return None


def collect_brightness() -> dict:
    """Get display brightness. Tries m1ddc (Apple Silicon external), falls back to brightness CLI."""
    # m1ddc: works with external displays on Apple Silicon (Mac Mini, etc.)
    m1ddc = _find_tool("m1ddc")
    if m1ddc:
        try:
            # Syntax: m1ddc display 1 get luminance (display selector before command)
            result = _run_as_user([m1ddc, "display", "1", "get", "luminance"])
            if result and result.returncode == 0:
                val = int(result.stdout.strip())
                return {"brightness": max(0, min(100, val))}
        except (ValueError, AttributeError):
            pass
    # Fallback: brightness CLI (works with built-in displays / older Macs)
    brightness_cli = _find_tool("brightness")
    if brightness_cli:
        try:
            result = _run_as_user([brightness_cli, "-l"])
            if result and result.returncode == 0:
                for line in result.stdout.splitlines():
                    if "brightness" in line.lower() and "display" in line.lower():
                        val = float(line.split()[-1])
                        return {"brightness": round(val * 100)}
        except (ValueError, IndexError, AttributeError):
            pass
    return {"brightness": None}


def collect_active_interface() -> dict:
    """Get the active network interface name from route table."""
    try:
        result = subprocess.run(
            ["route", "get", "default"],
            capture_output=True, text=True, timeout=5,
        )
        for line in result.stdout.splitlines():
            if "interface:" in line:
                return {"active_interface": line.split(":")[-1].strip()}
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass
    return {"active_interface": "unknown"}


def collect_time_machine() -> dict:
    """Get Time Machine status. Graceful if TM not configured."""
    data = {"tm_backing_up": False, "tm_last_backup": None}
    try:
        result = subprocess.run(
            ["tmutil", "status"],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode == 0:
            for line in result.stdout.splitlines():
                if "Running" in line and "=" in line:
                    val = line.split("=")[-1].strip().rstrip(";")
                    data["tm_backing_up"] = val == "1"
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass

    try:
        result = subprocess.run(
            ["tmutil", "latestbackup"],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode == 0 and result.stdout.strip():
            # Output is a path like /Volumes/backup/Backups.backupdb/.../2024-01-01-120000
            backup_path = result.stdout.strip()
            # Extract date from path component (e.g. "2026-02-16-105340.backup")
            date_part = os.path.basename(backup_path).replace(".backup", "")
            try:
                dt = datetime.strptime(date_part, "%Y-%m-%d-%H%M%S")
                data["tm_last_backup"] = dt.replace(tzinfo=timezone.utc).isoformat()
            except ValueError:
                data["tm_last_backup"] = backup_path
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass

    return data


def _docker_slug(name: str) -> str:
    """Convert a Docker container name to a safe slug for MQTT/HA entity IDs."""
    return re.sub(r'[^a-z0-9]+', '_', name.lower()).strip('_')


_ISO_TS_RE = re.compile(r"(\d{4}[-/]\d{2}[-/]\d{2}[T ]\d{2}:\d{2}:\d{2})")
_ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
_LEVEL_RE = re.compile(
    r"\b(ERROR|FATAL|CRITICAL|WARNING|WARN|ERR)\b", re.IGNORECASE,
)


def _parse_log_entry(line: str, error_levels: set) -> dict | None:
    """Try to parse a log line as structured JSON, return normalized dict or None.

    Returns a dict with keys: ts, level, msg, source.
    Returns None if the line isn't JSON or doesn't match error_levels.
    """
    json_start = line.find("{")
    if json_start == -1:
        return None
    try:
        obj = json.loads(line[json_start:])
    except (json.JSONDecodeError, ValueError):
        return None

    level = str(obj.get("level", "")).lower()
    if level not in error_levels:
        return None

    msg = obj.get("msg", obj.get("message", ""))
    source = obj.get("source", "")
    time_val = obj.get("time", obj.get("timestamp", obj.get("ts", "")))

    # Convert epoch ms to ISO string
    ts = ""
    if isinstance(time_val, (int, float)):
        if time_val > 1e12:  # epoch milliseconds
            time_val = time_val / 1000
        ts = datetime.fromtimestamp(time_val, tz=timezone.utc).strftime(
            "%Y-%m-%d %H:%M:%S"
        )
    elif isinstance(time_val, str):
        m = _ISO_TS_RE.match(time_val)
        ts = m.group(1) if m else time_val[:25]

    return {"ts": ts, "level": level, "msg": str(msg)[:200], "source": source}


def _is_error_line(line: str, error_re, exclude_re, error_levels: set) -> bool:
    """Check if a log line counts as an error using both JSON and regex matching."""
    clean = _ANSI_RE.sub("", line)
    if exclude_re and exclude_re.search(clean):
        return False
    # Try structured JSON first
    json_start = clean.find("{")
    if json_start != -1:
        try:
            obj = json.loads(clean[json_start:])
            level = str(obj.get("level", "")).lower()
            if level in error_levels:
                msg = str(obj.get("msg", obj.get("message", "")))
                return not (exclude_re and exclude_re.search(msg))
            return False
        except (json.JSONDecodeError, ValueError):
            pass
    # Regex fallback
    return bool(error_re.search(clean))


def collect_docker(cfg: dict) -> dict | None:
    """Collect Docker stats if enabled and docker CLI available."""
    docker_cfg = cfg.get("docker", {})
    if not docker_cfg.get("enabled", False):
        return None
    try:
        subprocess.run(["docker", "info"], capture_output=True, timeout=5, check=True)
    except (subprocess.TimeoutExpired, FileNotFoundError, subprocess.CalledProcessError):
        return {"docker_available": False, "docker_running_count": 0, "docker_unhealthy": False}

    data = {"docker_available": True}

    # Count running containers
    try:
        result = subprocess.run(
            ["docker", "ps", "-q"],
            capture_output=True, text=True, timeout=5,
        )
        lines = [l for l in result.stdout.strip().splitlines() if l]
        data["docker_running_count"] = len(lines)
    except (subprocess.TimeoutExpired, FileNotFoundError):
        data["docker_running_count"] = 0

    # Check for unhealthy containers
    try:
        result = subprocess.run(
            ["docker", "ps", "--filter", "health=unhealthy", "-q"],
            capture_output=True, text=True, timeout=5,
        )
        unhealthy = [l for l in result.stdout.strip().splitlines() if l]
        data["docker_unhealthy"] = len(unhealthy) > 0
    except (subprocess.TimeoutExpired, FileNotFoundError):
        data["docker_unhealthy"] = False

    # Error counting config
    error_window = docker_cfg.get("log_error_window", 300)
    error_lines_window = docker_cfg.get("log_error_lines_window", 86400)
    error_patterns = docker_cfg.get("log_error_patterns", [
        "error", "exception", "fatal", "traceback",
        r"failed: true", "auth_failed", "invalid_token",
        "missing_scope", "Connection failed", "ratelimited",
        "RateLimitError", "APIConnectionError",
    ])
    error_re = re.compile("|".join(error_patterns), re.IGNORECASE)
    exclude_patterns = docker_cfg.get("log_error_exclude_patterns", [
        r"error: none", r"errors: 0", r"0 errors",
        r"failed: false", r"connIndex=", r"pong.+received",
    ])
    exclude_re = re.compile("|".join(exclude_patterns), re.IGNORECASE) if exclude_patterns else None
    error_levels = set(docker_cfg.get("log_error_levels",
                                       ["error", "fatal", "critical", "err",
                                        "warn", "warning"]))
    total_errors = 0

    # Per-container status + error counting
    watched = docker_cfg.get("watched_containers", [])
    for name in watched:
        slug = _docker_slug(name)

        # Container status (running, exited, restarting, etc.)
        try:
            result = subprocess.run(
                ["docker", "inspect", "--format", "{{.State.Status}}", name],
                capture_output=True, text=True, timeout=5,
            )
            status = result.stdout.strip() if result.returncode == 0 else "unknown"
            data[f"docker_{slug}_status"] = status
            data[f"docker_{slug}_running"] = status == "running"
        except (subprocess.TimeoutExpired, FileNotFoundError):
            data[f"docker_{slug}_status"] = "unknown"
            data[f"docker_{slug}_running"] = False

        # Error count from recent logs (short window for charts)
        try:
            result = subprocess.run(
                ["docker", "logs", "--since", f"{error_window}s", name],
                capture_output=True, text=True, timeout=10,
            )
            combined = result.stdout + result.stderr
            count = sum(
                1 for line in combined.splitlines()
                if _is_error_line(line, error_re, exclude_re, error_levels)
            )
            data[f"docker_{slug}_errors"] = count
            total_errors += count
        except (subprocess.TimeoutExpired, FileNotFoundError):
            data[f"docker_{slug}_errors"] = 0

        # Structured error entries from longer window (24h) for dashboard
        try:
            result = subprocess.run(
                ["docker", "logs", "--since", f"{error_lines_window}s", name],
                capture_output=True, text=True, timeout=15,
            )
            combined = result.stdout + result.stderr
            entries: list[dict] = []
            for raw_line in combined.splitlines():
                stripped = raw_line.rstrip()
                if not stripped:
                    continue
                # Try structured JSON parse first
                entry = _parse_log_entry(stripped, error_levels)
                if entry:
                    if not (exclude_re and (
                        exclude_re.search(stripped) or exclude_re.search(entry["msg"])
                    )):
                        entries.append(entry)
                    continue
                # Fallback: regex match for unstructured logs
                clean = _ANSI_RE.sub("", stripped)
                if error_re.search(clean) and not (exclude_re and exclude_re.search(clean)):
                    ts = ""
                    msg = clean
                    # Extract timestamp from anywhere in the line
                    ts_match = _ISO_TS_RE.search(clean)
                    if ts_match:
                        ts = ts_match.group(1)
                        # Strip timestamp + surrounding chars from msg
                        before = clean[:ts_match.start()].rstrip(" [")
                        after = clean[ts_match.end():].lstrip(" |:.-]")
                        msg = (before + " " + after).strip() if before else after
                    # Detect actual log level from line
                    level = "error"
                    level_match = _LEVEL_RE.search(msg)
                    if level_match:
                        level = level_match.group(1).lower()
                        # Normalize warn/err variants
                        if level == "err":
                            level = "error"
                        if level == "warning":
                            level = "warn"
                    entries.append({
                        "ts": ts,
                        "level": level,
                        "msg": msg.strip()[:200],
                        "source": "",
                    })
            total_count = len(entries)
            recent = entries[-20:]  # keep last 20 for dashboard
            latest_ts = recent[-1]["ts"] if recent else ""
            data[f"docker_{slug}_error_entries"] = recent
            data[f"docker_{slug}_error_lines_count"] = total_count
            data[f"docker_{slug}_error_lines_latest"] = latest_ts
        except (subprocess.TimeoutExpired, FileNotFoundError):
            data[f"docker_{slug}_error_entries"] = []
            data[f"docker_{slug}_error_lines_count"] = 0
            data[f"docker_{slug}_error_lines_latest"] = ""

    data["docker_total_errors"] = total_errors

    return data


def collect_all(cfg: dict) -> dict:
    """Collect all sensor data into a single dict."""
    data = {}
    data.update(collect_cpu())
    data.update(collect_memory())
    data.update(collect_load())
    data.update(collect_disks(cfg.get("drives", [])))
    data.update(collect_network())
    data.update(collect_uptime())
    data.update(collect_idle_time())
    data.update(collect_display_sleep())
    data.update(collect_active_interface())
    data.update(collect_time_machine())
    data.update(collect_mic())
    data.update(collect_mic_in_use())

    brightness = collect_brightness()
    if brightness["brightness"] is not None:
        data.update(brightness)

    if cfg.get("cpu_temp_enabled"):
        temp = collect_cpu_temp()
        if temp:
            data.update(temp)

    docker_data = collect_docker(cfg)
    if docker_data:
        data.update(docker_data)

    # Keep-awake state — query Amphetamine app via AppleScript
    keep_awake = False
    try:
        result = _run_as_user([
            "osascript", "-e",
            'tell application "Amphetamine" to session is active',
        ])
        if result and result.returncode == 0:
            keep_awake = result.stdout.strip().lower() == "true"
    except Exception:
        pass
    data["keep_awake"] = keep_awake

    # Heartbeat
    data["heartbeat"] = datetime.now(timezone.utc).isoformat()

    return data


# ---------------------------------------------------------------------------
# MQTT auto-discovery
# ---------------------------------------------------------------------------
def device_info(cfg: dict) -> dict:
    return {
        "identifiers": [cfg["node_id"]],
        "name": cfg["device_name"],
        "model": cfg.get("device_model", "Mac mini"),
        "manufacturer": "Apple",
    }


def publish_discovery(client: mqtt.Client, cfg: dict) -> None:
    """Publish MQTT auto-discovery configs for all sensors, binary_sensors, buttons, etc."""
    node = cfg["node_id"]
    dev = device_info(cfg)
    state_topic = f"mac-monitor/{node}/state"
    avail_topic = f"mac-monitor/{node}/availability"
    avail = [{"topic": avail_topic}]

    discoveries = []

    # --- Sensors ---
    sensors = [
        ("cpu_percent", "CPU Usage", "%", "mdi:cpu-64-bit", None),
        ("ram_percent", "RAM Usage", "%", "mdi:memory", None),
        ("load_1m", "Load 1m", None, "mdi:gauge", None),
        ("load_5m", "Load 5m", None, "mdi:gauge", None),
        ("load_15m", "Load 15m", None, "mdi:gauge", None),
        ("net_sent_gb", "Network Sent", "GB", "mdi:upload-network", None),
        ("net_recv_gb", "Network Received", "GB", "mdi:download-network", None),
        ("uptime_days", "Uptime", "days", "mdi:clock-outline", None),
        ("user_idle_minutes", "User Idle Time", "min", "mdi:timer-sand", None),
        ("active_interface", "Active Interface", None, "mdi:ethernet", None),
        ("heartbeat", "Heartbeat", None, "mdi:heart-pulse", "timestamp"),
        ("tm_last_backup", "TM Last Backup", None, "mdi:backup-restore", "timestamp"),
    ]

    for key, name, unit, icon, dev_class in sensors:
        uid = f"{node}_{key}"
        payload = {
            "name": name,
            "unique_id": uid,
            "state_topic": state_topic,
            "value_template": f"{{{{ value_json.{key} }}}}",
            "icon": icon,
            "device": dev,
            "availability": avail,
        }
        if unit:
            payload["unit_of_measurement"] = unit
        if dev_class:
            payload["device_class"] = dev_class
        discoveries.append((f"homeassistant/sensor/{node}/{key}/config", payload))

    # CPU temp (optional)
    if cfg.get("cpu_temp_enabled"):
        uid = f"{node}_cpu_temp"
        discoveries.append((
            f"homeassistant/sensor/{node}/cpu_temp/config",
            {
                "name": "CPU Temperature",
                "unique_id": uid,
                "state_topic": state_topic,
                "value_template": "{{ value_json.cpu_temp | default('unavailable') }}",
                "unit_of_measurement": "\u00b0C",
                "device_class": "temperature",
                "icon": "mdi:thermometer",
                "device": dev,
                "availability": avail,
            },
        ))

    # Disk sensors
    for drv in cfg.get("drives", []):
        name_slug = drv["name"]
        label = drv.get("label", name_slug)
        uid = f"{node}_disk_{name_slug}_percent"
        discoveries.append((
            f"homeassistant/sensor/{node}/disk_{name_slug}_percent/config",
            {
                "name": f"Disk {label}",
                "unique_id": uid,
                "state_topic": state_topic,
                "value_template": f"{{{{ value_json.disk_{name_slug}_percent }}}}",
                "unit_of_measurement": "%",
                "icon": "mdi:harddisk",
                "device": dev,
                "availability": avail,
            },
        ))

    # --- Binary sensors ---
    bin_sensors = [
        ("display_asleep", "Display Asleep", "mdi:monitor-off", None),
        ("tm_backing_up", "Time Machine Backing Up", "mdi:backup-restore", None),
        ("mic_in_use", "Microphone In Use", "mdi:microphone", None),
    ]

    for key, name, icon, dev_class in bin_sensors:
        uid = f"{node}_{key}"
        payload = {
            "name": name,
            "unique_id": uid,
            "state_topic": state_topic,
            "value_template": f"{{{{ 'ON' if value_json.{key} else 'OFF' }}}}",
            "icon": icon,
            "device": dev,
            "availability": avail,
        }
        if dev_class:
            payload["device_class"] = dev_class
        discoveries.append((f"homeassistant/binary_sensor/{node}/{key}/config", payload))

    # Drive connected binary sensors
    for drv in cfg.get("drives", []):
        if drv["path"] == "/":
            continue  # Root is always mounted
        name_slug = drv["name"]
        label = drv.get("label", name_slug)
        uid = f"{node}_drive_{name_slug}_connected"
        discoveries.append((
            f"homeassistant/binary_sensor/{node}/drive_{name_slug}_connected/config",
            {
                "name": f"Drive {label} Connected",
                "unique_id": uid,
                "state_topic": state_topic,
                "value_template": f"{{{{ 'ON' if value_json.drive_{name_slug}_connected else 'OFF' }}}}",
                "device_class": "connectivity",
                "icon": "mdi:harddisk",
                "device": dev,
                "availability": avail,
            },
        ))

    # Docker sensors (if enabled)
    docker_cfg = cfg.get("docker", {})
    if docker_cfg.get("enabled"):
        discoveries.append((
            f"homeassistant/binary_sensor/{node}/docker_available/config",
            {
                "name": "Docker Available",
                "unique_id": f"{node}_docker_available",
                "state_topic": state_topic,
                "value_template": "{{ 'ON' if value_json.docker_available else 'OFF' }}",
                "device_class": "connectivity",
                "icon": "mdi:docker",
                "device": dev,
                "availability": avail,
            },
        ))
        discoveries.append((
            f"homeassistant/sensor/{node}/docker_running_count/config",
            {
                "name": "Docker Running Containers",
                "unique_id": f"{node}_docker_running_count",
                "state_topic": state_topic,
                "value_template": "{{ value_json.docker_running_count }}",
                "icon": "mdi:docker",
                "device": dev,
                "availability": avail,
            },
        ))
        discoveries.append((
            f"homeassistant/binary_sensor/{node}/docker_unhealthy/config",
            {
                "name": "Docker Unhealthy Containers",
                "unique_id": f"{node}_docker_unhealthy",
                "state_topic": state_topic,
                "value_template": "{{ 'ON' if value_json.docker_unhealthy else 'OFF' }}",
                "device_class": "problem",
                "icon": "mdi:docker",
                "device": dev,
                "availability": avail,
            },
        ))
        discoveries.append((
            f"homeassistant/sensor/{node}/docker_total_errors/config",
            {
                "name": "Docker Total Errors",
                "unique_id": f"{node}_docker_total_errors",
                "state_topic": state_topic,
                "value_template": "{{ value_json.docker_total_errors }}",
                "icon": "mdi:alert-circle",
                "device": dev,
                "availability": avail,
            },
        ))
        for cname in docker_cfg.get("watched_containers", []):
            slug = _docker_slug(cname)
            discoveries.append((
                f"homeassistant/binary_sensor/{node}/docker_{slug}_running/config",
                {
                    "name": f"Docker {cname}",
                    "unique_id": f"{node}_docker_{slug}_running",
                    "state_topic": state_topic,
                    "value_template": f"{{{{ 'ON' if value_json.docker_{slug}_running else 'OFF' }}}}",
                    "device_class": "running",
                    "icon": "mdi:docker",
                    "device": dev,
                    "availability": avail,
                },
            ))
            discoveries.append((
                f"homeassistant/sensor/{node}/docker_{slug}_status/config",
                {
                    "name": f"Docker {cname} Status",
                    "unique_id": f"{node}_docker_{slug}_status",
                    "state_topic": state_topic,
                    "value_template": f"{{{{ value_json.docker_{slug}_status }}}}",
                    "icon": "mdi:docker",
                    "device": dev,
                    "availability": avail,
                },
            ))
            discoveries.append((
                f"homeassistant/sensor/{node}/docker_{slug}_errors/config",
                {
                    "name": f"Docker {cname} Errors",
                    "unique_id": f"{node}_docker_{slug}_errors",
                    "state_topic": state_topic,
                    "value_template": f"{{{{ value_json.docker_{slug}_errors }}}}",
                    "icon": "mdi:alert-circle",
                    "device": dev,
                    "availability": avail,
                },
            ))
            # Separate error log sensor (24h window) for dashboard display
            discoveries.append((
                f"homeassistant/sensor/{node}/docker_{slug}_error_log/config",
                {
                    "name": f"Docker {cname} Error Log",
                    "unique_id": f"{node}_docker_{slug}_error_log",
                    "state_topic": state_topic,
                    "value_template": f"{{{{ value_json.docker_{slug}_error_lines_count }}}}",
                    "json_attributes_topic": state_topic,
                    "json_attributes_template": (
                        "{{ {'error_entries': value_json.docker_"
                        + slug
                        + "_error_entries, 'last_error_ts': value_json.docker_"
                        + slug
                        + "_error_lines_latest} | tojson }}"
                    ),
                    "icon": "mdi:text-box-search",
                    "device": dev,
                    "availability": avail,
                },
            ))

    # --- Controls ---
    controls = cfg.get("controls", {})
    cmd_base = f"mac-monitor/{node}/command"

    # Buttons
    buttons = [
        ("sleep", "Sleep", "mdi:power-sleep"),
        ("sleep_display", "Sleep Display", "mdi:monitor-off"),
        ("lock", "Lock", "mdi:lock"),
        ("shutdown", "Shutdown", "mdi:power"),
        ("restart", "Restart", "mdi:restart"),
    ]
    for key, name, icon in buttons:
        if not controls.get(key, False):
            continue
        uid = f"{node}_{key}"
        discoveries.append((
            f"homeassistant/button/{node}/{key}/config",
            {
                "name": name,
                "unique_id": uid,
                "command_topic": f"{cmd_base}/{key}",
                "icon": icon,
                "device": dev,
                "availability": avail,
            },
        ))

    # Reload button — always available, restarts the daemon
    discoveries.append((
        f"homeassistant/button/{node}/reload/config",
        {
            "name": "Reload Agent",
            "unique_id": f"{node}_reload",
            "command_topic": f"{cmd_base}/reload",
            "icon": "mdi:refresh",
            "device": dev,
            "availability": avail,
        },
    ))

    # Volume number + mute switch
    if controls.get("volume", False):
        discoveries.append((
            f"homeassistant/number/{node}/volume/config",
            {
                "name": "Volume",
                "unique_id": f"{node}_volume",
                "command_topic": f"{cmd_base}/volume",
                "state_topic": state_topic,
                "value_template": "{{ value_json.volume | default(50) }}",
                "min": 0,
                "max": 100,
                "step": 5,
                "icon": "mdi:volume-high",
                "device": dev,
                "availability": avail,
            },
        ))
        discoveries.append((
            f"homeassistant/switch/{node}/volume_mute/config",
            {
                "name": "Volume Mute",
                "unique_id": f"{node}_volume_mute",
                "command_topic": f"{cmd_base}/volume_mute",
                "state_topic": state_topic,
                "value_template": "{{ 'ON' if value_json.volume_muted else 'OFF' }}",
                "icon": "mdi:volume-off",
                "device": dev,
                "availability": avail,
            },
        ))

    # Mic Mute switch (always on)
    discoveries.append((
        f"homeassistant/switch/{node}/mic_mute/config",
        {
            "name": "Mic Mute",
            "unique_id": f"{node}_mic_mute",
            "command_topic": f"{cmd_base}/mic_mute",
            "state_topic": state_topic,
            "value_template": "{{ 'ON' if value_json.mic_muted else 'OFF' }}",
            "icon": "mdi:microphone-off",
            "device": dev,
            "availability": avail,
        },
    ))

    # Mic Volume number (slider 0-100)
    discoveries.append((
        f"homeassistant/number/{node}/mic_volume/config",
        {
            "name": "Mic Volume",
            "unique_id": f"{node}_mic_volume_ctrl",
            "command_topic": f"{cmd_base}/mic_volume",
            "state_topic": state_topic,
            "value_template": "{{ value_json.mic_volume | default(50) }}",
            "min": 0,
            "max": 100,
            "step": 5,
            "icon": "mdi:microphone",
            "device": dev,
            "availability": avail,
        },
    ))

    # Brightness number (works if `brightness` CLI is installed)
    discoveries.append((
        f"homeassistant/number/{node}/brightness/config",
        {
            "name": "Brightness",
            "unique_id": f"{node}_brightness",
            "command_topic": f"{cmd_base}/brightness",
            "state_topic": state_topic,
            "value_template": "{{ value_json.brightness | default(50) }}",
            "min": 0,
            "max": 100,
            "step": 5,
            "icon": "mdi:brightness-6",
            "device": dev,
            "availability": avail,
        },
    ))

    # Keep Awake switch
    if controls.get("keep_awake", False):
        discoveries.append((
            f"homeassistant/switch/{node}/keep_awake/config",
            {
                "name": "Keep Awake",
                "unique_id": f"{node}_keep_awake",
                "command_topic": f"{cmd_base}/keep_awake",
                "state_topic": state_topic,
                "value_template": "{{ 'ON' if value_json.keep_awake else 'OFF' }}",
                "icon": "mdi:coffee",
                "device": dev,
                "availability": avail,
            },
        ))

    # Shortcut buttons
    for shortcut_name in cfg.get("shortcuts", []):
        slug = shortcut_name.lower().replace(" ", "_").replace("-", "_")
        discoveries.append((
            f"homeassistant/button/{node}/shortcut_{slug}/config",
            {
                "name": f"Shortcut: {shortcut_name}",
                "unique_id": f"{node}_shortcut_{slug}",
                "command_topic": f"{cmd_base}/shortcut/{shortcut_name}",
                "icon": "mdi:apple-keyboard-command",
                "device": dev,
                "availability": avail,
            },
        ))

    # Publish all discoveries
    for topic, payload in discoveries:
        client.publish(topic, json.dumps(payload), retain=True, qos=1)
        logger.debug("Discovery: %s", topic)

    logger.info("Published %d discovery configs", len(discoveries))


# ---------------------------------------------------------------------------
# Command handlers
# ---------------------------------------------------------------------------
def handle_sleep(payload: str) -> None:
    logger.info("Command: sleep")
    subprocess.Popen(["pmset", "sleepnow"])


def handle_sleep_display(payload: str) -> None:
    logger.info("Command: sleep display")
    subprocess.Popen(["pmset", "displaysleepnow"])


def handle_lock(payload: str) -> None:
    logger.info("Command: lock screen")
    cgsession = (
        "/System/Library/CoreServices/Menu Extras/User.menu"
        "/Contents/Resources/CGSession"
    )
    _popen_as_user([cgsession, "-suspend"])


def handle_volume_mute(payload: str) -> None:
    desired = payload.strip().upper() in ("ON", "1", "TRUE")
    logger.info("Command: volume_mute %s", "ON (mute)" if desired else "OFF (unmute)")
    try:
        ca, Addr, targets = _get_coreaudio_output()
        if not targets:
            logger.warning("No output volume targets found for mute")
            return
        mute_sel = int.from_bytes(b"mute", "big")
        outp = int.from_bytes(b"outp", "big")
        val = ctypes.c_uint32(1 if desired else 0)
        for dev_id, ch in targets:
            addr = Addr(mute_sel, outp, ch)
            ca.AudioObjectSetPropertyData(dev_id, ctypes.byref(addr), 0, None, 4, ctypes.byref(val))
    except Exception:
        logger.exception("handle_volume_mute failed")
    time.sleep(0.3)
    _force_publish_state()


def handle_volume(payload: str) -> None:
    try:
        vol = int(float(payload))
        vol = max(0, min(100, vol))
    except (ValueError, TypeError):
        logger.warning("Invalid volume payload: %s", payload)
        return
    logger.info("Command: set volume to %d", vol)
    try:
        ca, Addr, targets = _get_coreaudio_output()
        if not targets:
            logger.warning("No output volume targets found")
            return
        volm = int.from_bytes(b"volm", "big")
        outp = int.from_bytes(b"outp", "big")
        new_vol = ctypes.c_float(vol / 100.0)
        for dev_id, ch in targets:
            addr = Addr(volm, outp, ch)
            ca.AudioObjectSetPropertyData(dev_id, ctypes.byref(addr), 0, None, 4, ctypes.byref(new_vol))
    except Exception:
        logger.exception("handle_volume failed")
    time.sleep(0.3)
    _force_publish_state()


def handle_keep_awake(payload: str) -> None:
    desired = payload.strip().upper() in ("ON", "1", "TRUE")
    logger.info("Command: keep_awake %s", "ON" if desired else "OFF")

    script = ('tell application "Amphetamine" to start new session with options {duration:0, interval:0, displaySleepAllowed:true}'
              if desired else
              'tell application "Amphetamine" to end session')
    result = _run_as_user(["osascript", "-e", script])
    if not result or result.returncode != 0:
        logger.warning("Amphetamine command failed: rc=%s stderr=%r",
                       getattr(result, "returncode", None),
                       getattr(result, "stderr", "").strip() if result else "")
        return
    logger.info("Amphetamine session %s", "started" if desired else "ended")
    # Publish state immediately so HA switch updates without waiting for next poll
    time.sleep(0.5)  # brief delay for Amphetamine to settle
    _force_publish_state()


def _set_mic_volume_coreaudio(pct: int) -> bool:
    """Set mic input volume (0-100) via CoreAudio HAL. Returns True on success."""
    try:
        ca, Addr, dev = _get_coreaudio()
        if ca is None:
            return False
        inp = int.from_bytes(b"inpt", "big")
        volm = int.from_bytes(b"volm", "big")
        addr = Addr(volm, inp, 1)  # channel 1
        new_vol = ctypes.c_float(pct / 100.0)
        return ca.AudioObjectSetPropertyData(dev, ctypes.byref(addr), 0, None, 4, ctypes.byref(new_vol)) == 0
    except Exception:
        logger.exception("CoreAudio set mic volume failed")
        return False


def handle_mic_mute(payload: str) -> None:
    desired = payload.strip().upper() in ("ON", "1", "TRUE")
    logger.info("Command: mic_mute %s", "ON (mute)" if desired else "OFF (unmute)")
    _set_mic_volume_coreaudio(0 if desired else 75)
    time.sleep(0.3)
    _force_publish_state()


def handle_mic_volume(payload: str) -> None:
    try:
        vol = int(float(payload))
        vol = max(0, min(100, vol))
    except (ValueError, TypeError):
        logger.warning("Invalid mic_volume payload: %s", payload)
        return
    logger.info("Command: set mic volume to %d", vol)
    _set_mic_volume_coreaudio(vol)
    time.sleep(0.3)
    _force_publish_state()


def handle_brightness(payload: str) -> None:
    try:
        level = int(float(payload))
        level = max(0, min(100, level))
    except (ValueError, TypeError):
        logger.warning("Invalid brightness payload: %s", payload)
        return
    logger.info("Command: set brightness to %d%%", level)
    # m1ddc: 0-100 integer for external displays on Apple Silicon
    # Set ALL connected displays (e.g. dual LG UltraFines on Mac Mini)
    m1ddc = _find_tool("m1ddc")
    if m1ddc:
        display_ids = []
        try:
            result = _run_as_user([m1ddc, "display", "list"])
            if result and result.returncode == 0:
                for line in result.stdout.splitlines():
                    m = re.match(r"\[(\d+)\]", line.strip())
                    if m:
                        display_ids.append(m.group(1))
        except Exception:
            pass
        if not display_ids:
            display_ids = ["1"]
        # Set displays sequentially — DDC is serial, concurrent writes get dropped
        # Syntax: m1ddc display N set luminance X (display selector goes BEFORE command)
        for did in display_ids:
            _run_as_user([m1ddc, "display", did, "set", "luminance", str(level)])
    else:
        # Fallback: brightness CLI uses 0.0-1.0 float
        brightness_cli = _find_tool("brightness")
        if brightness_cli:
            brightness_float = level / 100.0
            _popen_as_user([brightness_cli, str(brightness_float)])


def handle_reload(payload: str) -> None:
    """Restart the mac-monitor daemon. KeepAlive in LaunchDaemon auto-restarts."""
    global running
    logger.info("Command: reload — exiting for KeepAlive restart")
    running = False


def handle_shutdown(payload: str) -> None:
    logger.info("Command: shutdown in 1 minute")
    subprocess.Popen(["shutdown", "-h", "+1"])  # already root


def handle_restart(payload: str) -> None:
    logger.info("Command: restart in 1 minute")
    subprocess.Popen(["shutdown", "-r", "+1"])  # already root


def handle_shortcut(name: str, allowed: list[str]) -> None:
    if name not in allowed:
        logger.warning("Shortcut '%s' not in allowlist: %s", name, allowed)
        return
    logger.info("Command: run shortcut '%s'", name)
    _popen_as_user(["shortcuts", "run", name])


COMMAND_HANDLERS = {
    "sleep": handle_sleep,
    "sleep_display": handle_sleep_display,
    "lock": handle_lock,
    "volume": handle_volume,
    "volume_mute": handle_volume_mute,
    "keep_awake": handle_keep_awake,
    "mic_mute": handle_mic_mute,
    "mic_volume": handle_mic_volume,
    "brightness": handle_brightness,
    "reload": handle_reload,
    "shutdown": handle_shutdown,
    "restart": handle_restart,
}


# ---------------------------------------------------------------------------
# MQTT callbacks
# ---------------------------------------------------------------------------
def on_connect(client: mqtt.Client, userdata: dict, flags, reason_code, properties=None) -> None:
    cfg = userdata
    node = cfg["node_id"]

    if reason_code == 0:
        logger.info("MQTT connected to %s:%d", cfg["mqtt"]["host"], cfg["mqtt"]["port"])
        # Publish online
        client.publish(f"mac-monitor/{node}/availability", "online", retain=True, qos=1)
        # Publish discovery
        publish_discovery(client, cfg)
        # Subscribe to command topics
        cmd_base = f"mac-monitor/{node}/command"
        client.subscribe(f"{cmd_base}/#", qos=1)
        logger.info("Subscribed to %s/#", cmd_base)
    else:
        logger.error("MQTT connect failed: %s", reason_code)


def on_disconnect(client: mqtt.Client, userdata, flags, reason_code, properties=None) -> None:
    if reason_code != 0:
        logger.warning("MQTT disconnected unexpectedly (rc=%s), will auto-reconnect", reason_code)


def on_message(client: mqtt.Client, userdata: dict, msg: mqtt.MQTTMessage) -> None:
    cfg = userdata
    node = cfg["node_id"]
    cmd_base = f"mac-monitor/{node}/command/"
    topic = msg.topic
    payload = msg.payload.decode("utf-8", errors="replace")

    if not topic.startswith(cmd_base):
        return

    cmd_path = topic[len(cmd_base):]
    controls = cfg.get("controls", {})

    # Shortcut commands
    if cmd_path.startswith("shortcut/"):
        shortcut_name = cmd_path[len("shortcut/"):]
        handle_shortcut(shortcut_name, cfg.get("shortcuts", []))
        return

    # Standard commands
    if cmd_path in COMMAND_HANDLERS:
        if controls.get(cmd_path, False) or cmd_path in ("volume", "volume_mute", "keep_awake", "reload", "mic_mute", "mic_volume"):
            COMMAND_HANDLERS[cmd_path](payload)
        else:
            logger.warning("Command '%s' disabled in config", cmd_path)
    else:
        logger.warning("Unknown command: %s", cmd_path)


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
def _force_publish_state() -> None:
    """Immediately collect and publish current state (for responsive UI after commands)."""
    if not _mqtt_client or not _cfg:
        return
    try:
        data = collect_all(_cfg)
        data["volume"] = get_volume()
        data["volume_muted"] = get_volume_muted()
        topic = f"mac-monitor/{_cfg['node_id']}/state"
        _mqtt_client.publish(topic, json.dumps(data), qos=0)
        logger.debug("Force-published state after command")
    except Exception:
        logger.exception("Error in force publish")


def get_volume() -> int:
    """Get current output volume via CoreAudio (works with aggregate devices like LG Dual)."""
    try:
        ca, Addr, targets = _get_coreaudio_output()
        if not targets:
            return 50
        dev_id, ch = targets[0]
        addr = Addr(int.from_bytes(b"volm", "big"), int.from_bytes(b"outp", "big"), ch)
        vol = ctypes.c_float(0.0)
        sz = ctypes.c_uint32(4)
        if ca.AudioObjectGetPropertyData(dev_id, ctypes.byref(addr), 0, None, ctypes.byref(sz), ctypes.byref(vol)) == 0:
            return round(vol.value * 100)
    except Exception:
        logger.exception("get_volume failed")
    return 50


def get_volume_muted() -> bool:
    """Get current output mute state via CoreAudio (works with aggregate devices)."""
    try:
        ca, Addr, targets = _get_coreaudio_output()
        if not targets:
            return False
        dev_id, ch = targets[0]
        addr = Addr(int.from_bytes(b"mute", "big"), int.from_bytes(b"outp", "big"), ch)
        muted = ctypes.c_uint32(0)
        sz = ctypes.c_uint32(4)
        if ca.AudioObjectGetPropertyData(dev_id, ctypes.byref(addr), 0, None, ctypes.byref(sz), ctypes.byref(muted)) == 0:
            return bool(muted.value)
    except Exception:
        logger.exception("get_volume_muted failed")
    return False


def main() -> None:
    global running, _mqtt_client, _cfg

    parser = argparse.ArgumentParser(description="Mac Mini MQTT Monitor")
    parser.add_argument("--config", required=True, help="Path to config.json")
    parser.add_argument("--debug", action="store_true", help="Enable debug logging")
    args = parser.parse_args()

    # Logging
    level = logging.DEBUG if args.debug else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    # Load config
    cfg = load_config(args.config)
    node = cfg["node_id"]
    logger.info("Starting mac-monitor (node=%s)", node)

    # MQTT client
    client = mqtt.Client(
        callback_api_version=CallbackAPIVersion.VERSION2,
        client_id=f"mac-monitor-{node}",
        userdata=cfg,
    )
    client.username_pw_set(cfg["mqtt"]["username"], cfg["mqtt"]["password"])

    # LWT (Last Will and Testament)
    client.will_set(
        f"mac-monitor/{node}/availability",
        payload="offline",
        qos=1,
        retain=True,
    )

    # Callbacks
    client.on_connect = on_connect
    client.on_disconnect = on_disconnect
    client.on_message = on_message

    # Store globals for force-publish from command handlers
    _mqtt_client = client
    _cfg = cfg

    # Auto-reconnect
    client.reconnect_delay_set(min_delay=1, max_delay=120)

    # Signal handlers
    def signal_handler(signum, frame):
        global running
        logger.info("Received signal %d, shutting down...", signum)
        running = False

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    # Connect — use loop_forever with connect_async for resilient startup
    client.connect_async(cfg["mqtt"]["host"], cfg["mqtt"]["port"], keepalive=60)
    client.loop_start()

    # Prime psutil.cpu_percent() — first call with interval=None always returns 0
    psutil.cpu_percent(interval=None)

    # Main publish loop
    state_topic = f"mac-monitor/{node}/state"
    interval = cfg.get("publish_interval", 30)

    try:
        while running:
            try:
                data = collect_all(cfg)
                # Add current volume and mute state
                data["volume"] = get_volume()
                data["volume_muted"] = get_volume_muted()
                client.publish(state_topic, json.dumps(data), qos=0)
                logger.debug("Published state: %d keys", len(data))
            except Exception:
                logger.exception("Error collecting/publishing metrics")

            # Sleep in small increments so we can exit quickly
            for _ in range(interval * 2):
                if not running:
                    break
                time.sleep(0.5)
    finally:
        # Graceful shutdown
        logger.info("Shutting down...")

        # Publish offline
        try:
            client.publish(
                f"mac-monitor/{node}/availability",
                "offline",
                qos=1,
                retain=True,
            )
            time.sleep(0.5)  # Give time for the message to send
        except Exception:
            pass

        client.loop_stop()
        client.disconnect()
        logger.info("Goodbye")


if __name__ == "__main__":
    main()
