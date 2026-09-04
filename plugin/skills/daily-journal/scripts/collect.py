#!/usr/bin/env python3
"""Collect raw material for the daily work journal.

Usage:  collect.py [DATE] [--out DIR]
  DATE  = YYYY-MM-DD | today | yesterday   (default: today)
  DIR   = output directory
          (default: $CLAUDE_SCRATCHPAD/daily-journal/<date> if CLAUDE_SCRATCHPAD is set,
           else $TMPDIR/daily-journal/<date>)

Configuration: ~/.config/daily-journal/config.json (override with env DAILY_JOURNAL_CONFIG).
See config.example.json at the plugin root for all keys; only journal_dir is required.

Sources (each isolated; a failing source is reported, not fatal):
  git        commits by you on that day in every repo under git.roots (+ dirty trees, unpushed)
  claude     Claude Code sessions from <claude.projects_dir>/*/ transcripts (title, prompts, last answer)
  calendar   Google Calendar events of the day; "Notes by Gemini" docs exported to text
  gmail      received (non-promo) + sent mail of the day, with the message's own text
  drive      Google Docs modified that day (shared notes etc.), exported to text
  carryover  open and closed actions from the previous journal entry
  inbox      captures from the phone waiting in <journal_dir>/inbox/

Slack is NOT collected here (no CLI) - the skill fetches it through a Slack MCP tool if one is connected.
Writes <out>/raw.md (everything, for the model to read) plus per-source exported files.
Python 3.11+, standard library only.
"""
import datetime as dt
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from zoneinfo import ZoneInfo

# ---------- config ----------
CONFIG_PATH = os.environ.get("DAILY_JOURNAL_CONFIG") or os.path.expanduser("~/.config/daily-journal/config.json")
EXAMPLE_PATH = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "config.example.json"))
DEFAULTS = {
    "journal_dir": None,
    "timezone": None,
    "me": {"name": "", "email": ""},
    "git": {"roots": [], "depth": 1, "author": ""},
    "claude": {"projects_dir": "~/.claude/projects", "project_filter": []},
    "google": {
        "enabled": True,
        "calendar_id": "primary",
        "gmail_exclude_categories": ["promotions", "updates", "social", "forums"],
        "gmail_noise_senders": ["noreply", "no-reply", "notifications@", "calendar-notification", "gemini-notes@"],
    },
    "slack": {"enabled": True, "handle": ""},
}


def load_config():
    if not os.path.exists(CONFIG_PATH):
        print(f"daily-journal: no config file at {CONFIG_PATH}", file=sys.stderr)
        print("Create it (env DAILY_JOURNAL_CONFIG overrides the path). Only journal_dir is required. Example:", file=sys.stderr)
        try:
            print(open(EXAMPLE_PATH, encoding="utf-8").read(), file=sys.stderr)
        except OSError:
            print(json.dumps({"journal_dir": "~/Journal", "timezone": "Europe/Helsinki",
                              "me": {"name": "Your Name", "email": "you@example.com"},
                              "git": {"roots": ["~/Coding"], "depth": 1, "author": "Your Name"}}, indent=2), file=sys.stderr)
        sys.exit(2)
    with open(CONFIG_PATH, encoding="utf-8") as fh:
        user = json.load(fh)
    cfg = {}
    for k, v in DEFAULTS.items():
        if isinstance(v, dict):
            cfg[k] = {**v, **(user.get(k) or {})}
        else:
            cfg[k] = user.get(k, v)
    if not cfg["journal_dir"]:
        print(f"daily-journal: journal_dir is missing in {CONFIG_PATH}", file=sys.stderr)
        sys.exit(2)
    cfg["journal_dir"] = os.path.expanduser(cfg["journal_dir"])
    cfg["git"]["roots"] = [os.path.expanduser(r) for r in (cfg["git"]["roots"] or [])]
    cfg["claude"]["projects_dir"] = os.path.expanduser(cfg["claude"]["projects_dir"])
    return cfg


CFG = load_config()
TZ = ZoneInfo(CFG["timezone"]) if CFG["timezone"] else dt.datetime.now().astimezone().tzinfo
ME_EMAIL = (CFG["me"].get("email") or "").lower()
ME_NAME = CFG["me"].get("name") or ""
GIT_AUTHOR = CFG["git"].get("author") or ME_NAME
JOURNAL_DIR = CFG["journal_dir"]
INBOX_DIR = os.path.join(JOURNAL_DIR, "inbox")
HOME = os.path.expanduser("~")

# ---------- args ----------
args = list(sys.argv[1:])
out_dir = None
if "--out" in args:
    i = args.index("--out")
    out_dir = args[i + 1]
    del args[i:i + 2]
today = dt.datetime.now(TZ).date()
if not args or args[0] == "today":
    day = today
elif args[0] == "yesterday":
    day = today - dt.timedelta(days=1)
else:
    day = dt.date.fromisoformat(args[0])
start = dt.datetime.combine(day, dt.time.min, TZ)
end = start + dt.timedelta(days=1)
start_utc = start.astimezone(dt.timezone.utc)
end_utc = end.astimezone(dt.timezone.utc)
if not out_dir:
    base = os.environ.get("CLAUDE_SCRATCHPAD") or os.environ.get("TMPDIR") or tempfile.gettempdir()
    out_dir = os.path.join(base, "daily-journal", str(day))
os.makedirs(out_dir, exist_ok=True)

sections = []   # (title, markdown)
problems = []

GWS = shutil.which("gws")
GOOGLE_ENABLED = bool(CFG["google"].get("enabled", True))
GOOGLE_SKIP_REASON = None
if not GOOGLE_ENABLED:
    GOOGLE_SKIP_REASON = "_Google sources disabled in config (`google.enabled` is false)._"
elif not GWS:
    GOOGLE_SKIP_REASON = ("_`gws` CLI not found on PATH - skipped. Install with "
                          "`brew install googleworkspace/tap/gws` and run `gws auth login`, then re-run._")


def sh(cmd, cwd=None, timeout=120):
    r = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    return r.stdout, r.stderr, r.returncode


def gws(argv, timeout=120):
    """Run gws, strip the keyring banner, return parsed JSON (or None)."""
    r = subprocess.run([GWS] + argv, capture_output=True, text=True, timeout=timeout)
    txt = "\n".join(l for l in r.stdout.splitlines() if not l.startswith("Using keyring"))
    try:
        return json.loads(txt)
    except Exception:
        if "No messages found" in (r.stderr + txt):
            return {"messages": []}   # gws +triage reports an empty result as text, not JSON
        problems.append(f"gws {' '.join(argv[:3])}: {r.stderr.strip()[:200] or txt[:200]}")
        return None


def write(name, text):
    with open(os.path.join(out_dir, name), "w", encoding="utf-8") as f:
        f.write(text)


def short_path(p):
    for root in CFG["git"]["roots"]:
        if p.startswith(root + "/"):
            return p[len(root) + 1:]
    if p.startswith(HOME + "/"):
        return "~/" + p[len(HOME) + 1:]
    return p


# ---------- 1. git ----------
def find_repos():
    """Repos under git.roots. depth 1 = the root and its children; depth 2 = also grandchildren,
    but the children of a directory that is itself a repo are not descended into."""
    depth = int(CFG["git"].get("depth") or 1)
    found = []
    for root in CFG["git"]["roots"]:
        if not os.path.isdir(root):
            problems.append(f"git root missing: {root}")
            continue
        if os.path.isdir(os.path.join(root, ".git")):
            found.append(root)
        for child in sorted(os.listdir(root)):
            cp = os.path.join(root, child)
            if child.startswith(".") or not os.path.isdir(cp):
                continue
            if os.path.isdir(os.path.join(cp, ".git")):
                found.append(cp)
                continue
            if depth >= 2:
                for gc in sorted(os.listdir(cp)):
                    gp = os.path.join(cp, gc)
                    if not gc.startswith(".") and os.path.isdir(gp) and os.path.isdir(os.path.join(gp, ".git")):
                        found.append(gp)
    return found


def collect_git():
    if not CFG["git"]["roots"]:
        return "_No `git.roots` configured._"
    if not GIT_AUTHOR:
        return "_No `git.author` (or `me.name`) configured - cannot filter commits._"
    lines = []
    repos = find_repos()
    for p in repos:
        repo = short_path(p) if p not in CFG["git"]["roots"] else os.path.basename(p) + " (root)"
        out, _, _ = sh(f'git log --all --author="{GIT_AUTHOR}" --since="{start.isoformat()}" --until="{end.isoformat()}" '
                       f'--date=format-local:%H:%M --format="%h%x09%ad%x09%D%x09%s" --no-merges', cwd=p)
        commits = [l for l in out.splitlines() if l.strip()]
        dirty, _, _ = sh("git status --porcelain | wc -l", cwd=p)
        branch, _, _ = sh("git rev-parse --abbrev-ref HEAD", cwd=p)
        unpushed, _, _ = sh("git log @{u}..HEAD --oneline 2>/dev/null | wc -l", cwd=p)
        if commits or int(unpushed.strip() or 0) > 0:
            lines.append(f"### {repo} (branch {branch.strip()}, {dirty.strip()} dirty files, {unpushed.strip()} unpushed commits)")
            for c in commits:
                h, t, deco, s = (c.split("\t") + ["", "", ""])[:4]
                deco = f" [{deco}]" if deco else ""
                lines.append(f"- `{h}` {t}{deco} - {s}")
            lines.append("")
    header = f"_Scanned {len(repos)} repos under {', '.join(short_path(r) for r in CFG['git']['roots'])} (author filter `{GIT_AUTHOR}`)._"
    if not lines:
        lines.append("_No commits by you on this day in any repo._")
    return "\n".join([header, ""] + lines)


# ---------- 2. claude sessions ----------
def pretty_project(dirname):
    """~/.claude/projects/<dir> names are the cwd with '/' replaced by '-'; strip the home prefix."""
    home_key = HOME.replace("/", "-")
    if dirname.startswith(home_key + "-"):
        return dirname[len(home_key) + 1:]
    return dirname


def collect_claude():
    pdir = CFG["claude"]["projects_dir"]
    if not os.path.isdir(pdir):
        return f"_Claude projects dir not found: {pdir}_"
    filt = [s for s in (CFG["claude"].get("project_filter") or []) if s]
    rows = []
    for f in glob.glob(os.path.join(pdir, "*", "*.jsonl")):
        if dt.datetime.fromtimestamp(os.path.getmtime(f), TZ) < start:
            continue
        dirname = os.path.basename(os.path.dirname(f))
        if filt and not any(s in dirname for s in filt):
            continue
        project = pretty_project(dirname)
        title = None; prompts = []; last_assist = None; first = None; last = None
        tools = 0; continued = False; files_touched = set()
        try:
            with open(f, encoding="utf-8") as fh:
                for line in fh:
                    try:
                        d = json.loads(line)
                    except Exception:
                        continue
                    t = d.get("type")
                    if t == "ai-title":
                        title = d.get("aiTitle")
                    ts = d.get("timestamp")
                    if not ts:
                        continue
                    tsd = dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))
                    if not (start_utc <= tsd < end_utc):
                        continue
                    if d.get("isSidechain"):
                        continue
                    first = first or tsd; last = tsd
                    msg = d.get("message", {})
                    if t == "user" and not d.get("isMeta"):
                        c = msg.get("content")
                        if isinstance(c, str) and not c.startswith("<"):
                            if c.startswith("This session is being continued"):
                                continued = True
                            else:
                                prompts.append(c.strip().replace("\n", " ")[:160])
                    if t == "assistant":
                        for b in msg.get("content", []) or []:
                            if not isinstance(b, dict):
                                continue
                            if b.get("type") == "text" and b["text"].strip():
                                last_assist = b["text"].strip()
                            elif b.get("type") == "tool_use":
                                tools += 1
                                fp = (b.get("input") or {}).get("file_path")
                                if fp and b.get("name") in ("Edit", "Write", "MultiEdit"):
                                    files_touched.add(short_path(fp))
        except Exception as e:
            problems.append(f"claude transcript {os.path.basename(f)}: {e}")
            continue
        if first and (prompts or last_assist):
            rows.append(dict(first=first.astimezone(TZ), last=last.astimezone(TZ), project=project,
                             title=title, prompts=prompts, answer=last_assist, tools=tools,
                             continued=continued, files=sorted(files_touched), id=os.path.basename(f)[:8]))
    rows.sort(key=lambda r: r["first"])
    if not rows:
        return "_No Claude Code sessions on this day._"
    lines = []
    for r in rows:
        cont = " (continued session)" if r["continued"] else ""
        lines.append(f"### {r['first']:%H:%M}-{r['last']:%H:%M} · {r['title'] or '(untitled)'} · project {r['project']} · {r['tools']} tool calls{cont} · id {r['id']}")
        for p in r["prompts"][:6]:
            lines.append(f"- prompt: {p}")
        if len(r["prompts"]) > 6:
            lines.append(f"- ... {len(r['prompts']) - 6} more prompts")
        if r["files"]:
            lines.append(f"- files edited: {', '.join(r['files'][:12])}" + (" ..." if len(r["files"]) > 12 else ""))
        if r["answer"]:
            answer = r["answer"][:700].replace("\n", " ")
            lines.append(f"- last answer: {answer}")
        lines.append("")
    return "\n".join(lines)


# ---------- 3. calendar + gemini notes ----------
def export_doc(file_id, name):
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "_", name)[:80]
    fname = f"doc-{safe}.txt"
    path = os.path.join(out_dir, fname)
    # gws only writes -o paths inside its cwd, so run it from the output dir
    r = subprocess.run([GWS, "drive", "files", "export", "--params",
                        json.dumps({"fileId": file_id, "mimeType": "text/plain"}), "-o", fname],
                       capture_output=True, text=True, timeout=120, cwd=out_dir)
    if not os.path.exists(path):
        problems.append(f"export {name}: {r.stderr.strip()[:200]}")
        return None
    return path


def gemini_summary(path):
    """Quick notes + Summary + Next steps from a Gemini notes doc, without the transcript."""
    txt = open(path, encoding="utf-8", errors="replace").read()
    m = re.search(r"^Details\s*$", txt, re.M)
    head = txt[: m.start()] if m else txt[:6000]
    head = re.sub(r"Want to see more\?.*?Meeting records[^\n]*\n", "", head, flags=re.S)
    head = re.sub("^\ufeff", "", head)
    head = re.sub(r"\n{3,}", "\n\n", head).strip()
    return head[:6000]


def collect_calendar():
    if GOOGLE_SKIP_REASON:
        return GOOGLE_SKIP_REASON
    d = gws(["calendar", "events", "list", "--params", json.dumps({
        "calendarId": CFG["google"].get("calendar_id") or "primary",
        "timeMin": start_utc.isoformat().replace("+00:00", "Z"),
        "timeMax": end_utc.isoformat().replace("+00:00", "Z"), "singleEvents": True,
        "orderBy": "startTime", "maxResults": 50})])
    if d is None:
        return "_calendar unavailable_"
    lines = []
    if ME_NAME:
        lines.append(f"_In Gemini \"Next steps\", lines tagged `[{ME_NAME}]` or `[The group]` are yours; other assignees are context only._")
        lines.append("")
    for e in d.get("items", []):
        st = e.get("start", {})
        when = st.get("dateTime", st.get("date", ""))
        when = when[11:16] if "T" in when else "all-day"
        attendees = e.get("attendees", []) or []
        att = [a.get("email", "") for a in attendees if (a.get("email") or "").lower() != ME_EMAIL]
        resp = next((a.get("responseStatus") for a in attendees if (a.get("email") or "").lower() == ME_EMAIL), None)
        lines.append(f"### {when} · {e.get('summary')}" + (f" · ({resp})" if resp else ""))
        if att:
            lines.append(f"- with: {', '.join(att[:12])}")
        desc = re.sub(r"<[^>]+>", " ", e.get("description") or "").strip()
        if desc:
            lines.append(f"- description: {desc[:300]}")
        for a in e.get("attachments", []) or []:
            lines.append(f"- attachment: {a.get('title')} - {a.get('fileUrl')}")
            if "Notes by Gemini" in (a.get("title") or "") and a.get("fileId"):
                p = export_doc(a["fileId"], f"{when}-{e.get('summary')}-gemini")
                if p:
                    lines.append(f"- Gemini notes (full text incl. transcript at {p}):")
                    lines.append("")
                    lines.append("```")
                    lines.append(gemini_summary(p))
                    lines.append("```")
        lines.append("")
    return "\n".join(lines) if lines else "_No calendar events._"


# ---------- 4. gmail ----------
def gmail_list(query, maxn):
    d = gws(["gmail", "+triage", "--query", query, "--max", str(maxn), "--format", "json"])
    if not d:
        return []
    return d.get("messages", []) if isinstance(d, dict) else d


def gmail_meta(mid):
    d = gws(["gmail", "users", "messages", "get", "--params", json.dumps({
        "userId": "me", "id": mid, "format": "metadata", "metadataHeaders": ["Subject", "From", "To", "Date"]})])
    if not d:
        return {}
    h = {x["name"]: x["value"] for x in d.get("payload", {}).get("headers", [])}
    return dict(subject=h.get("Subject"), frm=h.get("From"), to=h.get("To"), date=h.get("Date"),
                snippet=d.get("snippet", ""), labels=d.get("labelIds", []), thread=d.get("threadId"))


QUOTE_RE = re.compile(r"^(On .{5,120} wrote:|Lähettäjä:|From: .*|-----Original Message-----|\d{1,2}\.\d{1,2}\.\d{4} .{0,60} kirjoitti:).*$", re.M)
NOISE_SENDERS = tuple(s.lower() for s in (CFG["google"].get("gmail_noise_senders") or []))


def gmail_body(mid, limit=700):
    """Own text of the message (quoted history stripped), via gws gmail +read."""
    d = gws(["gmail", "+read", "--id", mid, "--format", "json"])
    if not d:
        return ""
    b = d.get("body_text") or ""
    m = QUOTE_RE.search(b)
    if m:
        b = b[: m.start()]
    b = "\n".join(l for l in b.splitlines() if not l.lstrip().startswith(">"))
    b = re.sub(r"\n\s*\n+", "\n", b).strip()
    return b[:limit]


def collect_gmail():
    if GOOGLE_SKIP_REASON:
        return GOOGLE_SKIP_REASON
    a = f"{day:%Y/%m/%d}"; b = f"{end.date():%Y/%m/%d}"
    excl = " ".join(f"-category:{c}" for c in (CFG["google"].get("gmail_exclude_categories") or []))
    recv = gmail_list(f"after:{a} before:{b} {excl} -in:sent".strip(), 40)
    sent = gmail_list(f"in:sent after:{a} before:{b}", 20)
    lines = [f"### Received ({len(recv)})"]
    for m in recv:
        meta = gmail_meta(m["id"])
        lab = [l for l in meta.get("labels", []) if l in ("UNREAD", "IMPORTANT", "STARRED")]
        lines.append(f"- **{meta.get('subject') or m.get('subject')}** - from {meta.get('frm') or m.get('from')} · {(meta.get('date') or '')[:22]}"
                     + (f" · {'/'.join(lab)}" if lab else "") + f" · id {m['id']}")
        frm = (meta.get("frm") or m.get("from") or "").lower()
        if not any(n in frm for n in NOISE_SENDERS):
            body = gmail_body(m["id"])
            if body:
                lines += [f"  > {l}" for l in body.splitlines()[:12]]
    lines.append(""); lines.append(f"### Sent ({len(sent)})")
    for m in sent:
        meta = gmail_meta(m["id"])
        lines.append(f"- **{meta.get('subject')}** - to {meta.get('to')} · {(meta.get('date') or '')[:22]} · id {m['id']}")
        body = gmail_body(m["id"], 900)
        if body:
            lines += [f"  > {l}" for l in body.splitlines()[:20]]
    return "\n".join(lines)


# ---------- 5. drive docs modified that day ----------
def collect_drive():
    if GOOGLE_SKIP_REASON:
        return GOOGLE_SKIP_REASON
    q = (f"mimeType='application/vnd.google-apps.document' and modifiedTime > '{start_utc.isoformat()[:19]}' "
         f"and modifiedTime < '{end_utc.isoformat()[:19]}' and not name contains 'Notes by Gemini'")
    d = gws(["drive", "files", "list", "--params", json.dumps({
        "q": q, "orderBy": "modifiedTime desc", "pageSize": 20,
        "fields": "files(id,name,modifiedTime,webViewLink,owners(emailAddress),lastModifyingUser(emailAddress))"})])
    if d is None:
        return "_drive unavailable_"
    files = d.get("files", [])
    if not files:
        return "_No Google Docs modified on this day (excluding Gemini notes)._"
    lines = []
    for f in files:
        who = (f.get("lastModifyingUser") or {}).get("emailAddress", "?")
        p = export_doc(f["id"], f["name"])
        size = os.path.getsize(p) if p else 0
        lines.append(f"- **{f['name']}** - modified {f['modifiedTime'][:16]} by {who} - {f.get('webViewLink')}")
        if p:
            lines.append(f"  text exported to {p} ({size} bytes) - read it (`sed -n 1,120p`) if the title looks relevant")
    return "\n".join(lines)


# ---------- 6. previous journal carry-over ----------
ENTRY_RE = re.compile(r"^\d{4}-\d{2}-\d{2}\.md$")


def section(txt, name):
    """Body of a `## <name>` section (case-insensitive), up to the next `## ` heading or EOF."""
    m = re.search(rf"^##\s*{re.escape(name)}\s*$(.*?)(?=^##\s|\Z)", txt, re.S | re.M | re.I)
    return m.group(1) if m else ""


def collect_carryover():
    if not os.path.isdir(JOURNAL_DIR):
        return f"_Journal dir not found: {JOURNAL_DIR}_"
    prev = sorted(f for f in glob.glob(os.path.join(JOURNAL_DIR, "*.md"))
                  if ENTRY_RE.match(os.path.basename(f)) and os.path.basename(f)[:10] < str(day))
    if not prev:
        return "_No earlier journal entry._"
    p = prev[-1]
    txt = open(p, encoding="utf-8").read()
    open_items, closed_items = [], []
    for name in ("Actions", "Carried over"):
        for l in section(txt, name).splitlines():
            s = l.strip()
            if s.startswith("- [ ]"):
                open_items.append(s)
            elif s.startswith("- [x]") or s.startswith("- [X]"):
                closed_items.append(s)
    lines = [f"From {os.path.basename(p)} (sections Actions + Carried over):", ""]
    lines.append(f"Open ({len(open_items)}) - copy into today's `## Carried over` unless closed today:")
    lines += open_items or ["_(no open actions)_"]
    lines.append("")
    lines.append(f"Closed since ({len(closed_items)}) - already `[x]`, do NOT carry forward; may be mentioned as done:")
    lines += closed_items or ["_(none)_"]
    return "\n".join(lines)


# ---------- 7. inbox captures from the phone ----------
HEADER_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):[ \t]*(.*)$")
FNAME_DATE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})")


def parse_capture(path):
    """Parse an inbox capture per JOURNAL_FORMAT.md: `key: value` header lines up to the first empty line, then body."""
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
        "kind": (meta.get("kind") or "note").lower(),
        "created": meta.get("created") or (fm.group(1) if fm else ""),
        "device": meta.get("device") or "",
        "body": body,
    }


def list_inbox():
    if not os.path.isdir(INBOX_DIR):
        return []
    files = sorted(f for f in glob.glob(os.path.join(INBOX_DIR, "*.md")) if os.path.isfile(f))
    return [parse_capture(f) for f in files]


def collect_inbox():
    caps = list_inbox()
    if not caps:
        return "_No inbox captures._"
    lines = [f"_{len(caps)} capture(s) in {INBOX_DIR}. `action` captures become `- [ ] <body> - source: <device> <created>` under `## Actions`; "
             f"`note` captures go into Done or Details. Archive them after writing the entry with `inbox.py archive`._", ""]
    for c in caps:
        lines.append(f"### {c['file']} · kind: {c['kind']} · created {c['created'] or '?'}" + (f" · device {c['device']}" if c["device"] else ""))
        lines += [f"> {l}" for l in (c["body"].splitlines() or ["_(empty body)_"])]
        lines.append("")
    return "\n".join(lines)


# ---------- run ----------
for title, fn in [("Git commits", collect_git), ("Claude Code sessions", collect_claude),
                  ("Calendar & meeting notes", collect_calendar), ("Gmail", collect_gmail),
                  ("Google Docs modified", collect_drive), ("Carry-over from previous journal", collect_carryover),
                  ("Inbox (from phone)", collect_inbox)]:
    try:
        sections.append((title, fn()))
    except Exception as e:
        problems.append(f"{title}: {e!r}")
        sections.append((title, f"_failed: {e!r}_"))

tzname = getattr(TZ, "key", None) or str(TZ)
raw = [f"# Raw journal material for {day} ({day:%A})", f"Window: {start.isoformat()} -> {end.isoformat()} ({tzname})",
       f"Journal dir: {JOURNAL_DIR}", ""]
for t, body in sections:
    raw += [f"## {t}", "", body, ""]
if CFG["slack"].get("enabled", True):
    handle = CFG["slack"].get("handle") or "<handle>"
    raw += ["## Slack", "", f"_Not collected by this script - if a Slack MCP search tool is connected, the skill runs the "
            f"`from:@{handle}` / `to:@{handle}` / `@{handle}` queries (see SKILL.md). Otherwise note 'Slack: not connected'._", ""]
else:
    raw += ["## Slack", "", "_Slack disabled in config (`slack.enabled` is false)._", ""]
if problems:
    raw += ["## Collection problems", ""] + [f"- {p}" for p in problems]
write("raw.md", "\n".join(raw))
print(f"date={day} out={out_dir}")
print(f"raw={os.path.join(out_dir, 'raw.md')}")
for t, body in sections:
    print(f"  {t}: {len(body.splitlines())} lines")
if problems:
    print("problems:")
    for p in problems:
        print("  -", p)
