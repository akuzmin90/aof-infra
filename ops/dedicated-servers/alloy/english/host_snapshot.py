#!/usr/bin/env python3
"""Bounded Linux resource/service snapshots, forwarded by Alloy to Loki."""
import datetime
import json
import os
from pathlib import Path
import subprocess
import time

DIRECTORY = Path("/var/lib/alloy/host-snapshots")
UNITS = ("tomcat.service", "postgresql@11-main.service", "nginx.service")
MOUNTS = ("/", "/boot")
MAX_BYTES = 8 * 1024 * 1024


def cpu_percent(previous, current, same_boot):
    if not same_boot or previous is None or len(previous) != len(current):
        return None
    delta = [b - a for a, b in zip(previous, current)]
    if any(x < 0 for x in delta) or sum(delta) == 0:
        return None
    return round(100 * (sum(delta) - delta[3] - delta[4]) / sum(delta), 3)


def memory_values(text):
    values = {}
    for line in text.splitlines():
        key, value = line.split(":", 1)
        values[key] = int(value.strip().split()[0]) * 1024
    total, available = values["MemTotal"], values["MemAvailable"]
    return {"memory_total_bytes": total, "memory_available_bytes": available,
            "memory_used_percent": round(100 * (total - available) / total, 3),
            "swap_total_bytes": values.get("SwapTotal", 0),
            "swap_used_bytes": values.get("SwapTotal", 0) - values.get("SwapFree", 0)}


def service_values(text, units=UNITS):
    parsed = {}
    for block in text.strip().split("\n\n"):
        fields = dict(line.split("=", 1) for line in block.splitlines() if "=" in line)
        if fields.get("Id"):
            parsed[fields["Id"]] = fields
    rows = []
    for unit in units:
        fields = parsed.get(unit, {})
        state = fields.get("ActiveState")
        try:
            pid = int(fields["MainPID"])
        except (KeyError, ValueError):
            state, pid = None, None
        row = {"kind": "service", "unit": unit, "state": state or "unknown",
               "collection_ok": int(state is not None), "active": -1}
        if state is not None:
            row.update(active=int(state == "active" and pid > 0), main_pid=pid)
        rows.append(row)
    return rows


def disk_values(mount, stat):
    total = stat.f_blocks * stat.f_frsize
    available = stat.f_bavail * stat.f_frsize
    used = (stat.f_blocks - stat.f_bfree) * stat.f_frsize
    row = {"kind": "filesystem", "mount": mount, "collection_ok": 1,
           "disk_total_bytes": total, "disk_available_bytes": available,
           "disk_used_percent": round(100 * used / (used + available), 3)}
    if stat.f_files:
        row["inode_used_percent"] = round(100 * (stat.f_files - stat.f_ffree) / stat.f_files, 3)
    return row


def append_records(path, rows, maximum=MAX_BYTES):
    payload = "".join(json.dumps(row, sort_keys=True, allow_nan=False) + "\n" for row in rows)
    if len(payload.encode()) > 16384:
        raise RuntimeError("Snapshot exceeds fixed size bound")
    if path.exists() and path.stat().st_size + len(payload.encode()) > maximum:
        second = path.with_name(path.name + ".2")
        first = path.with_name(path.name + ".1")
        if first.exists():
            os.replace(str(first), str(second))
        os.replace(str(path), str(first))
    with path.open("a") as out:
        out.write(payload)


def collect(directory=DIRECTORY):
    os.umask(0o077)
    state_file = directory / "cpu-state.json"
    try:
        previous = json.loads(state_file.read_text())
    except (FileNotFoundError, ValueError):
        previous = {}
    if not isinstance(previous, dict) or not isinstance(previous.get("cpu", []), list):
        previous = {}
    # Linux includes guest time in user/nice already: exclude guest and guest_nice.
    cpu = [int(x) for x in Path("/proc/stat").read_text().splitlines()[0].split()[1:9]]
    boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
    now = time.time()
    common = {"sample_unix": round(now, 3), "host": "mland",
              "observed_at": datetime.datetime.fromtimestamp(now, datetime.timezone.utc).isoformat()}
    host = dict(common, kind="host", collection_ok=1)
    host.update(memory_values(Path("/proc/meminfo").read_text()))
    usage = cpu_percent(previous.get("cpu"), cpu, previous.get("boot") == boot)
    if usage is not None:
        host["cpu_used_percent"] = usage
    host.update(cpu_count=os.cpu_count(), load_1=os.getloadavg()[0],
                uptime_seconds=float(Path("/proc/uptime").read_text().split()[0]))
    rows = [host]
    for mount in MOUNTS:
        try:
            row = disk_values(mount, os.statvfs(mount))
        except OSError as error:
            row = {"kind": "filesystem", "mount": mount, "collection_ok": 0,
                   "error_type": type(error).__name__}
        rows.append(dict(common, **row))
    try:
        result = subprocess.run(["/bin/systemctl", "show", "--no-pager",
                                 "--property=Id,LoadState,ActiveState,MainPID", *UNITS],
                                capture_output=True, text=True, timeout=2)
        text = result.stdout
    except (OSError, subprocess.TimeoutExpired):
        text = ""
    rows.extend(dict(common, **row) for row in service_values(text))
    append_records(directory / "observations.jsonl", rows)
    temporary = state_file.with_suffix(".tmp")
    temporary.write_text(json.dumps({"cpu": cpu, "boot": boot}))
    os.replace(str(temporary), str(state_file))
    print("Resource snapshot written: {} bounded records".format(len(rows)))


if __name__ == "__main__":
    collect()
