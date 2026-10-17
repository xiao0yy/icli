#!/usr/bin/env python3
"""Command contract checks; never request permissions or modify real calendars."""
import json
import re
from pathlib import Path
import subprocess
import sys

binary = sys.argv[1] if len(sys.argv) > 1 else "dist/icli"
checks = 0

def run(args, expected=None):
    global checks
    result = subprocess.run([binary, *args], text=True, capture_output=True, timeout=15)
    if expected is not None:
        assert result.returncode == expected, (args, result.returncode, result.stdout, result.stderr)
    checks += 1
    return result

for path in [[], ["cal"], ["cal", "auth"], ["cal", "calendars"], ["cal", "events"],
             ["cal", "auth", "status"], ["cal", "auth", "request"],
             ["cal", "calendars", "list"],
             *[["cal", "events", command] for command in ["list", "get", "create", "update", "delete"]]]:
    assert "USAGE:" in run([*path, "--help"], 0).stdout
for command in ["today", "upcoming", "search", "ls", "list", "show", "add", "update", "delete"]:
    assert "USAGE:" in run(["cal", command, "--help"], 0).stdout
for path in [["cal", "sources"], ["cal", "sources", "list"],
             *[["cal", "calendars", command] for command in ["create", "update", "delete"]]]:
    assert "USAGE:" in run([*path, "--help"], 0).stdout
version_source = Path(__file__).resolve().parents[1] / "Sources/CLICore/Version.swift"
expected_version = re.search(r'public static let current = "([^"\n]+)"', version_source.read_text()).group(1)
assert run(["--version"], 0).stdout.strip() == expected_version
for args in [["doctor", "--json"], ["--json", "doctor"], ["cal", "auth", "status", "--json"]]:
    result = run(args, 0)
    assert json.loads(result.stdout)["ok"] is True
    assert not result.stderr, result.stderr

invalid = [
    ["cal", "events", "create"],
    ["cal", "events", "create", "--title", "test", "--start", "2026-10-14T10:00", "--end", "2026-10-14T11:00"],
    ["cal", "events", "create", "--title", "test", "--all-day", "--start", "2026-02-30", "--end", "2026-03-01"],
    ["cal", "events", "create", "--title", "test", "--start", "2026-02-30T10:00:00+08:00", "--end", "2026-03-01T11:00:00+08:00"],
    ["cal", "events", "list", "--from", "2026-10-15", "--to", "2026-10-14"],
    ["cal", "events", "update", "fake-id"],
    ["cal", "events", "update", "fake-id", "--location", "office", "--clear-location"],
    ["cal", "events", "delete", "fake-id"],
    ["unknown-command"],
    ["cal", "upcoming", "--days", "0"],
    ["cal", "upcoming", "-d", "366"],
    ["cal", "today", "--limit", "0"],
    ["cal", "search", " "],
    ["cal", "list", "--sort", "unknown"],
    ["cal", "add", "First title", "--title", "Second title", "-s", "2026-10-14T10:00:00+08:00", "-e", "2026-10-14T11:00:00+08:00", "--dry-run"],
    ["cal", "calendars", "create", "test", "--color", "red", "--dry-run"],
    ["cal", "calendars", "update", "fake", "--color", "#XX0000", "--dry-run"],
    ["cal", "calendars", "update", "fake"],
    ["cal", "calendars", "delete", "fake"],
    ["cal", "list", "--attendee", " "],
    ["cal", "update", "fake", "--alert", "bad"],
    ["cal", "update", "fake", "--alert", "15m", "--no-alert"],
    ["cal", "update", "fake", "--title", "test", "--scope", "bad"],
    ["cal", "delete", "fake", "--scope", "bad", "--dry-run"],
    ["cal", "update", "fake", "--repeat", "hourly"],
    ["cal", "update", "fake", "--repeat", "daily", "--repeat-days", "mon"],
    ["cal", "update", "fake", "--repeat-interval", "2"],
    ["cal", "update", "fake", "--repeat", "daily", "--repeat-count", "0"],
    ["cal", "update", "fake", "--repeat", "daily", "--repeat-interval", "0"],
    ["cal", "update", "fake", "--repeat", "daily", "--repeat-count", "2", "--repeat-until", "2027-01-01"],
    ["cal", "update", "fake", "--repeat", "daily", "--clear-repeat"],
]
for args in invalid:
    result = run(["--json", *args], 2)
    body = json.loads(result.stdout)
    assert body["ok"] is False and body["error"]["code"] == "INVALID_ARGUMENT", body
    assert not result.stderr, result.stderr

status = json.loads(run(["cal", "auth", "status", "--json"], 0).stdout)["data"]
if not status["fullAccess"]:
    result = run(["cal", "calendars", "list", "--json"], 3)
    assert json.loads(result.stdout)["error"]["code"] == "PERMISSION_REQUIRED"
else:
    for args in [["cal", "events", "get", "icli-does-not-exist"],
                 ["cal", "events", "update", "icli-does-not-exist", "--title", "never saved", "--dry-run"],
                 ["cal", "events", "delete", "icli-does-not-exist", "--dry-run"]]:
        assert json.loads(run([*args, "--json"], 4).stdout)["error"]["code"] == "NOT_FOUND"
    assert json.loads(run(["cal", "events", "get", "icli-occ:invalid", "--json"], 2).stdout)["error"]["code"] == "INVALID_ARGUMENT"
    calendars = json.loads(run(["cal", "calendars", "--json"], 0).stdout)["data"]
    writable = next((c for c in calendars if c["writable"]), None)
    if writable:
        preview = json.loads(run(["cal", "add", "icli-preview-only", "-c", writable["id"],
                                  "-s", "2050-01-01T10:00:00+08:00", "-e", "2050-01-01T11:00:00+08:00",
                                  "--repeat", "daily", "--repeat-count", "2", "--dry-run", "--json"], 0).stdout)["data"]
        assert preview["dryRun"] and preview["event"]["recurring"] and preview["event"]["id"] == ""
print(f"Passed {checks} CLI checks (no calendar writes).")
