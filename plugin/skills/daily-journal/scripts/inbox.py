#!/usr/bin/env python3
"""Manage phone captures in <journal_dir>/inbox/ (see JOURNAL_FORMAT.md).

Usage:
  inbox.py list                          print every capture directly in inbox/ as JSON
  inbox.py archive [--date YYYY-MM-DD] [--dry-run]
                                         move every capture directly in inbox/ to inbox/archive/YYYY-MM/
                                         (month from the `created` header, else the file-name date,
                                          else --date, else today); never overwrites (-1, -2 suffix)

Configuration: ~/.config/daily-journal/config.json (override with env DAILY_JOURNAL_CONFIG).
Python 3.11+, standard library only.
"""
import datetime as dt
import glob
import json
import os
import re
import sys

CONFIG_PATH = os.environ.get("DAILY_JOURNAL_CONFIG") or os.path.expanduser("~/.config/daily-journal/config.json")
HEADER_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):[ \t]*(.*)$")
FNAME_DATE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})")
MONTH_RE = re.compile(r"^(\d{4}-\d{2})")


def journal_dir():
    if not os.path.exists(CONFIG_PATH):
        print(f"daily-journal: no config file at {CONFIG_PATH} (see config.example.json)", file=sys.stderr)
        sys.exit(2)
    with open(CONFIG_PATH, encoding="utf-8") as fh:
        cfg = json.load(fh)
    jd = cfg.get("journal_dir")
    if not jd:
        print(f"daily-journal: journal_dir is missing in {CONFIG_PATH}", file=sys.stderr)
        sys.exit(2)
    return os.path.expanduser(jd)


def parse_capture(path):
    """`key: value` header lines up to the first empty line (or first non-header line), then the body."""
    txt = open(path, encoding="utf-8", errors="replace").read().replace("\r\n", "\n").lstrip("\ufeff")
    lines = txt.split("\n")
    meta = {}
    i = 0
    while i < len(lines):
        l = lines[i]
        if l.strip() == "":
            i += 1
            break
        m = HEADER_RE.match(l)
        if not m:
            break
        meta[m.group(1).lower()] = m.group(2).strip()
        i += 1
    body = "\n".join(lines[i:]).strip()
    name = os.path.basename(path)
    fm = FNAME_DATE_RE.match(name)
    return {
        "file": name,
        "path": path,
        "kind": (meta.get("kind") or "note").lower(),
        "created": meta.get("created") or (fm.group(1) if fm else ""),
        "device": meta.get("device") or "",
        "body": body,
    }


def captures(inbox):
    if not os.path.isdir(inbox):
        return []
    files = sorted(f for f in glob.glob(os.path.join(inbox, "*.md")) if os.path.isfile(f))
    return [parse_capture(f) for f in files]


def month_of(cap, fallback):
    for cand in (cap.get("created") or "", cap["file"]):
        m = MONTH_RE.match(cand)
        if m:
            return m.group(1)
    return fallback[:7]


def unique_dest(dest_dir, name):
    base, ext = os.path.splitext(name)
    cand = os.path.join(dest_dir, name)
    n = 1
    while os.path.exists(cand):
        cand = os.path.join(dest_dir, f"{base}-{n}{ext}")
        n += 1
    return cand


def cmd_list(inbox):
    rows = [{k: v for k, v in c.items() if k != "path"} for c in captures(inbox)]
    print(json.dumps(rows, indent=2, ensure_ascii=False))


def cmd_archive(inbox, fallback_date, dry_run):
    caps = captures(inbox)
    if not caps:
        print("inbox: nothing to archive")
        return
    moved = 0
    for c in caps:
        dest_dir = os.path.join(inbox, "archive", month_of(c, fallback_date))
        dest = unique_dest(dest_dir, c["file"])
        rel = os.path.relpath(dest, inbox)
        if dry_run:
            print(f"would move {c['file']} -> {rel}")
            continue
        os.makedirs(dest_dir, exist_ok=True)
        os.rename(c["path"], dest)
        print(f"moved {c['file']} -> {rel}")
        moved += 1
    print(f"inbox: {'would archive' if dry_run else 'archived'} {len(caps) if dry_run else moved} capture(s)")


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0
    cmd, rest = argv[0], argv[1:]
    inbox = os.path.join(journal_dir(), "inbox")
    if cmd == "list":
        cmd_list(inbox)
        return 0
    if cmd == "archive":
        dry = "--dry-run" in rest
        fallback = dt.date.today().isoformat()
        if "--date" in rest:
            i = rest.index("--date")
            if i + 1 >= len(rest):
                print("--date needs a value YYYY-MM-DD", file=sys.stderr)
                return 2
            fallback = dt.date.fromisoformat(rest[i + 1]).isoformat()
        cmd_archive(inbox, fallback, dry)
        return 0
    print(f"unknown command {cmd!r}\n\n{__doc__.strip()}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
