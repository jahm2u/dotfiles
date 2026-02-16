#!/usr/bin/env python3
"""Mac Mini MQTT Monitor — publishes system metrics to Home Assistant via MQTT auto-discovery."""

from __future__ import annotations  # PEP 604 union types (X | Y) on Python 3.9

import argparse
import json
import logging
import os
import shutil
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import psutil
import paho.mqtt.client as mqtt
from paho.mqtt.enums import CallbackAPIVersion

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
logger = logging.getLogger("mac-monitor")
running = True
caffeinate_proc: subprocess.Popen | None = None
keep_awake_state = False


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
    return {"cpu_percent": psutil.cpu_percent(interval=1)}


def collect_memory() -> dict:
    mem = psutil.virtual_memory()
    return {"ram_percent": round(mem.percent, 1)}


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
        mounted = os.path.ismount(path) if path != "/" else True
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


def collect_mic() -> dict:
    """Get microphone muted state via osascript (must run in user session)."""
    try:
        result = _run_as_user(
            ["osascript", "-e", "input volume of (get volume settings)"],
        )
        if result and result.returncode == 0:
            input_vol = int(result.stdout.strip())
            return {"mic_muted": input_vol == 0, "mic_volume": input_vol}
    except (ValueError, AttributeError):
        pass
    return {"mic_muted": False, "mic_volume": 0}


def collect_brightness() -> dict:
    """Get display brightness. Tries m1ddc (Apple Silicon external), falls back to brightness CLI."""
    # m1ddc: works with external displays on Apple Silicon (Mac Mini, etc.)
    try:
        result = _run_as_user(["m1ddc", "get", "luminance"])
        if result and result.returncode == 0:
            val = int(result.stdout.strip())
            return {"brightness": max(0, min(100, val))}
    except (ValueError, AttributeError):
        pass
    # Fallback: brightness CLI (works with built-in displays / older Macs)
    try:
        result = _run_as_user(["brightness", "-l"])
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
            # Extract date from the last path component
            date_part = os.path.basename(backup_path)
            try:
                dt = datetime.strptime(date_part, "%Y-%m-%d-%H%M%S")
                data["tm_last_backup"] = dt.replace(tzinfo=timezone.utc).isoformat()
            except ValueError:
                data["tm_last_backup"] = backup_path
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass

    return data


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

    # Per-container status for watched containers
    watched = docker_cfg.get("watched_containers", [])
    for name in watched:
        try:
            result = subprocess.run(
                ["docker", "inspect", "--format", "{{.State.Running}}", name],
                capture_output=True, text=True, timeout=5,
            )
            data[f"docker_{name}_running"] = result.stdout.strip().lower() == "true"
        except (subprocess.TimeoutExpired, FileNotFoundError, subprocess.CalledProcessError):
            data[f"docker_{name}_running"] = False

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

    # Keep-awake state — detect actual caffeinate process
    global keep_awake_state, caffeinate_proc
    if caffeinate_proc and caffeinate_proc.poll() is not None:
        # Our caffeinate died unexpectedly
        caffeinate_proc = None
        keep_awake_state = False
    if not keep_awake_state:
        # Check if caffeinate is running externally (e.g. started by user)
        try:
            result = subprocess.run(
                ["pgrep", "-x", "caffeinate"],
                capture_output=True, text=True, timeout=3,
            )
            if result.returncode == 0 and result.stdout.strip():
                keep_awake_state = True
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass
    data["keep_awake"] = keep_awake_state

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
        ("mic_volume", "Mic Volume", "%", "mdi:microphone", None),
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
        for cname in docker_cfg.get("watched_containers", []):
            discoveries.append((
                f"homeassistant/binary_sensor/{node}/docker_{cname}_running/config",
                {
                    "name": f"Docker {cname}",
                    "unique_id": f"{node}_docker_{cname}_running",
                    "state_topic": state_topic,
                    "value_template": f"{{{{ 'ON' if value_json.docker_{cname}_running else 'OFF' }}}}",
                    "device_class": "running",
                    "icon": "mdi:docker",
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

    # Volume number
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


def handle_volume(payload: str) -> None:
    try:
        vol = int(float(payload))
        vol = max(0, min(100, vol))
    except (ValueError, TypeError):
        logger.warning("Invalid volume payload: %s", payload)
        return
    logger.info("Command: set volume to %d", vol)
    # osascript volume is 0-100 — must run in user session for audio
    _popen_as_user(["osascript", "-e", f"set volume output volume {vol}"])


def handle_keep_awake(payload: str) -> None:
    global caffeinate_proc, keep_awake_state
    desired = payload.strip().upper() in ("ON", "1", "TRUE")
    logger.info("Command: keep_awake %s", "ON" if desired else "OFF")

    if desired and not keep_awake_state:
        # Start caffeinate
        try:
            caffeinate_proc = subprocess.Popen(
                ["caffeinate", "-dimsu"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            keep_awake_state = True
            logger.info("caffeinate started (PID %d)", caffeinate_proc.pid)
        except FileNotFoundError:
            logger.error("caffeinate not found")
    elif not desired and keep_awake_state:
        # Stop caffeinate — kill our process or any external one
        if caffeinate_proc and caffeinate_proc.poll() is None:
            caffeinate_proc.terminate()
            caffeinate_proc.wait(timeout=5)
            logger.info("caffeinate stopped (our PID %d)", caffeinate_proc.pid)
        else:
            # Kill externally-started caffeinate processes
            try:
                subprocess.run(["pkill", "-x", "caffeinate"], timeout=5)
                logger.info("caffeinate stopped (external)")
            except (subprocess.TimeoutExpired, FileNotFoundError):
                pass
        caffeinate_proc = None
        keep_awake_state = False


def handle_mic_mute(payload: str) -> None:
    desired = payload.strip().upper() in ("ON", "1", "TRUE")
    logger.info("Command: mic_mute %s", "ON (mute)" if desired else "OFF (unmute)")
    if desired:
        _popen_as_user(["osascript", "-e", "set volume input volume 0"])
    else:
        _popen_as_user(["osascript", "-e", "set volume input volume 75"])


def handle_brightness(payload: str) -> None:
    try:
        level = int(float(payload))
        level = max(0, min(100, level))
    except (ValueError, TypeError):
        logger.warning("Invalid brightness payload: %s", payload)
        return
    logger.info("Command: set brightness to %d%%", level)
    # m1ddc: 0-100 integer for external displays on Apple Silicon
    if shutil.which("m1ddc"):
        _popen_as_user(["m1ddc", "set", "luminance", str(level)])
    else:
        # Fallback: brightness CLI uses 0.0-1.0 float
        brightness_float = level / 100.0
        _popen_as_user(["brightness", str(brightness_float)])


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
    "keep_awake": handle_keep_awake,
    "mic_mute": handle_mic_mute,
    "brightness": handle_brightness,
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
        if controls.get(cmd_path, False) or cmd_path in ("volume", "keep_awake"):
            COMMAND_HANDLERS[cmd_path](payload)
        else:
            logger.warning("Command '%s' disabled in config", cmd_path)
    else:
        logger.warning("Unknown command: %s", cmd_path)


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
def get_volume() -> int:
    """Get current macOS output volume (must run in user session)."""
    try:
        result = _run_as_user(
            ["osascript", "-e", "output volume of (get volume settings)"],
        )
        if result and result.returncode == 0:
            return int(result.stdout.strip())
    except (ValueError, AttributeError):
        pass
    return 50


def main() -> None:
    global running

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

    # Main publish loop
    state_topic = f"mac-monitor/{node}/state"
    interval = cfg.get("publish_interval", 30)

    try:
        while running:
            try:
                data = collect_all(cfg)
                # Add current volume
                data["volume"] = get_volume()
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

        # Stop caffeinate if running
        if caffeinate_proc and caffeinate_proc.poll() is None:
            caffeinate_proc.terminate()

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
