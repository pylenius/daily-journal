#!/bin/bash
# SessionStart hook (optional): surface the open actions from the latest daily journal.
# Prints a hookSpecificOutput JSON with additionalContext, or nothing when no journal/config exists.
# Reads journal_dir from ~/.config/daily-journal/config.json (env DAILY_JOURNAL_CONFIG overrides the path).
python3 - <<'EOF'
import glob, json, os, re, sys
cfg_path = os.environ.get("DAILY_JOURNAL_CONFIG") or os.path.expanduser("~/.config/daily-journal/config.json")
try:
    with open(cfg_path, encoding="utf-8") as fh:
        journal_dir = os.path.expanduser(json.load(fh).get("journal_dir") or "")
except Exception:
    sys.exit(0)
entries = sorted(f for f in glob.glob(os.path.join(journal_dir, "????-??-??.md"))
                 if re.match(r"^\d{4}-\d{2}-\d{2}\.md$", os.path.basename(f)))
if not entries:
    sys.exit(0)
p = entries[-1]
txt = open(p, encoding="utf-8").read()
items = []
for sec in ("Actions", "Carried over"):
    m = re.search(rf"^##\s*{sec}\s*$.*?(?=^##\s|\Z)", txt, re.S | re.M | re.I)
    if m:
        items += [l.strip() for l in m.group(0).splitlines() if l.strip().startswith("- [ ]")]
if not items:
    sys.exit(0)
ctx = (f"Open actions from the latest daily journal ({os.path.basename(p)}), for context only - "
       f"do not act on them unless asked:\n" + "\n".join(items[:25]))
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": ctx}}))
EOF
