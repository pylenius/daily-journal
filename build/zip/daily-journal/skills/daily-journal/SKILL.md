---
name: daily-journal
description: Write the daily work journal for one day — a short "done" list, an actions list with sources, and a longer details section with references — by combining git commits across your repos, Claude Code session transcripts, Google Calendar meetings with their Gemini notes, Gmail (received + sent), Google Docs edited that day, Slack (what you wrote, what was sent to you, mentions) and quick captures from your phone. Writes one YYYY-MM-DD.md file per day into the configured journal folder and carries unfinished actions forward from the previous entry. Use when the user says "journal", "daily journal", "write today's/yesterday's journal", "what did I do today/yesterday", "end of day summary", "day summary", "what's open from yesterday", "action items from today", "/daily-journal", or asks for a journal for a specific date. Also use when they ask "what did I promise / what's waiting for my reply" for a recent day.
---

# Daily work journal

One Markdown file per day in `<journal_dir>/YYYY-MM-DD.md` (`journal_dir` comes from `~/.config/daily-journal/config.json`). Three audiences in one file: a 10-second "what happened" list, an actions checklist that survives to the next day, and the long tail of details with links so any item can be picked up later.

The file format is a contract shared with the phone app that reads the journal and captures inbox notes: **see `JOURNAL_FORMAT.md` in the repository** (`spec/JOURNAL_FORMAT.md`). The skeleton, checkbox syntax, carry-over identity rule and inbox capture format below follow it; when in doubt, the spec wins.

The journal is **local and private**. It contains customer names, contract figures from meeting notes and email excerpts. Never publish it as an artifact, never paste it into chat tools or shared notes, and do not commit it unless the user explicitly asks.

## Inputs

- No args → **today**. `yesterday` → yesterday. `YYYY-MM-DD` → that day. Several days → run the whole procedure once per day, oldest first (so carry-over chains correctly).
- Day boundaries are local midnight in the configured `timezone`; the script handles the UTC conversion.

## Step 0 — Configuration

All scripts read `~/.config/daily-journal/config.json` (env `DAILY_JOURNAL_CONFIG` overrides the path). If it is missing, the collector prints the expected content and exits with code 2; show that to the user and stop. Keys: `journal_dir` (required), `timezone`, `me.name`/`me.email`, `git.roots`/`git.depth`/`git.author`, `claude.projects_dir`/`claude.project_filter`, `google.*`, `slack.handle`. `config.example.json` at the plugin root documents them.

## Step 1 — Collect the raw material (script)

`${CLAUDE_PLUGIN_ROOT}` is set when this skill is installed as a plugin. When it was copied or symlinked into a `.claude/skills/` folder instead, the scripts live in the `scripts/` directory next to this SKILL.md — resolve the real path (`readlink -f`) and use that.


```bash
CLAUDE_SCRATCHPAD=<your scratchpad dir> python3 ${CLAUDE_PLUGIN_ROOT}/skills/daily-journal/scripts/collect.py <date>
```

It takes 1–3 minutes when Google sources are enabled (Gmail bodies and Doc exports are one `gws` call each). Output goes to `$CLAUDE_SCRATCHPAD/daily-journal/<date>/` (or `$TMPDIR/daily-journal/<date>/`; `--out DIR` overrides). It prints the path of `raw.md`; **read that whole file**. It contains:

| Section | What it holds | Where it comes from |
|---|---|---|
| Git commits | your commits that day per repo (hash, time, branch decorations), plus dirty-file and unpushed-commit counts | `git log --all --author=<git.author>` in every repo under `git.roots` |
| Claude Code sessions | per session: time span, AI title, project, tool-call count, your prompts, files edited, the last answer | `<claude.projects_dir>/*/*.jsonl` — all projects unless `project_filter` narrows it |
| Calendar & meeting notes | events with attendees, description, attachments; **Gemini notes inlined** (quick notes, summary, decisions, next steps — transcript left in the exported file) | `gws calendar events list` + `gws drive files export` |
| Gmail | received (configured categories filtered out) and sent, with the message's own text (quoted history stripped) | `gws gmail +triage` / `+read` |
| Google Docs modified | docs edited that day by anyone, exported to text next to raw.md | `gws drive files list` |
| Carry-over | open `- [ ]` lines from **both** `## Actions` and `## Carried over` of the previous entry, plus the `- [x]` lines closed there | latest `YYYY-MM-DD.md` in `journal_dir` older than the day |
| Inbox (from phone) | every capture waiting in `<journal_dir>/inbox/`: file name, kind, created, device, body | files written by the phone app |
| Collection problems | any source that failed — mention these in the journal footer | |

The Google sections need the `gws` CLI (`brew install googleworkspace/tap/gws`, then `gws auth login`). The collector says so in the raw file when `gws` is missing or `google.enabled` is false; when it is installed but not authenticated the sections report the error — run `gws auth login` and re-run.

## Step 2 — Slack (MCP, not scriptable)

If a Slack MCP server with a message-search tool is connected (tool name contains `slack_search`), run these three queries using `slack.handle` from the config, with `D` = the journal day and `D-1` / `D+1` the neighbouring dates; page while more pages exist:

1. `from:@<handle> after:D-1 before:D+1` — what you said and to whom
2. `to:@<handle> after:D-1 before:D+1` — DMs to you
3. `@<handle> -from:@<handle> after:D-1 before:D+1` — channel mentions

Group by channel (a DM's channel name is usually the other person's user id; the author field on `to:` results gives the name). For a thread where someone asked you something, check whether your reply came after their message; if the context is unclear, open the thread with the server's thread tool if it has one. Keep each Slack reference as the permalink.

If no such tool is connected, write `Slack: not connected` in Sources & gaps and continue.

## Step 3 — Read what the raw file points at

- Gemini notes are already inline. The "Next steps" lines carry an assignee in brackets: `[<me.name>]` and `[The group]` items become actions; others are context only.
- For a modified Google Doc whose title looks relevant (shared 1:1 notes, meeting agendas, a customer's spec) open the exported text with `sed -n 1,120p`; notes docs are usually newest-first, so the top is the day's content.
- For a Claude session whose last answer is a plan, a question, or an API error, the work is unfinished — that is an action, referenced by session id and plan file.
- Inbox captures: `kind: action` → an action line; `kind: note` → Done or Details, whichever fits.

## Step 4 — Decide what counts

**Done** = something that changed state that day: a commit pushed, a page shipped, a sheet filled, a decision taken in a meeting, a question answered for a colleague, an investigation with a conclusion. One line each, most important first, at most ~12 lines. Group tiny related items.

**Action** = something waiting on you, with the evidence:
- a Gemini next step assigned to you or the group
- a mail or Slack message from a colleague, customer or partner that asks something and has no reply from you after it (check Sent and your Slack messages)
- something you promised ("later today", "I'll get back to you", "will be released next week")
- code that is committed but unpushed, or edited but uncommitted in a repo where you were working that day
- a Claude session that ended in a plan, an unanswered question, or an error
- a phone capture with `kind: action`
- an item carried over from the previous journal that is still open

Skip cold outreach, newsletters, vendor invitations, calendar acceptances and automated notifications — mention them at most as one line in the details ("3 cold sales mails ignored"). Personal or side projects go into a single **Other projects** line, never into Done.

**Carry-over rule** (from the format spec): copy every open `- [ ]` from **both** `## Actions` and `## Carried over` of the previous entry into today's `## Carried over`, appending `(from YYYY-MM-DD)` with the date of the entry the item first appeared in if it already has such a note, otherwise the previous entry's date. Items already `[x]` in the previous entry are **not** carried; you may mention them in Done if they closed that day. If today's evidence shows a carried item was done (a commit, a sent reply, a Slack answer), write it as `- [x] … — done: …` so the chain closes visibly. Keep the action text identical when carrying: readers match items across days by the text before ` — source:` / ` — done:` with the `(from …)` note removed, whitespace collapsed and case ignored. Rewording an item makes it a new one.

## Step 5 — Write the file

Use exactly this skeleton so the carry-over parser and the phone app keep working:

```markdown
# Journal — YYYY-MM-DD (Weekday)

## Done
- …

## Actions
- [ ] … — source: <email subject (id)> | <Slack permalink> | <meeting + doc link> | <repo commit/path>
- [ ] <inbox capture body> — source: <device> <created>

## Carried over
- [ ] … (from YYYY-MM-DD)
- [x] … — done: …

## Details

### Meetings
### Code & Claude Code sessions
### Email
### Slack
### Other projects
### Sources & gaps
- collector problems, sources that were unavailable, repos skipped, "Slack: not connected", inbox captures archived
```

Rules for the body:
- Every action and most details carry a reference the reader can open: commit hash + repo, Claude session id (first 8 chars) and plan path, Gmail message id and subject, Slack permalink, Google Doc link, ticket number.
- Write in English even when the source is another language; quote a sentence verbatim only when the wording matters.
- Time-critical or customer-facing items go first in Actions.
- Don't restate the Gemini transcript. Keep decisions and numbers; the doc link is the archive.
- No YAML front matter; the date comes from the file name.

Write with the Write tool to `<journal_dir>/YYYY-MM-DD.md` (create the folder if missing). If the file already exists, read it first and **merge**: keep manual edits and checked boxes (the phone may have ticked some), add what's new, never drop an action the user ticked.

**After the file is written**, fold the inbox away:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/daily-journal/scripts/inbox.py archive
```

It moves every capture in `inbox/` to `inbox/archive/YYYY-MM/` and prints what it moved. Mention the archived count in Sources & gaps (edit the line in the file you just wrote). Do not archive if you did not write the entry.

## Step 6 — Report

Show the user the Done list and the Actions list verbatim (they are short), then the file path. Do not repeat the details section in chat.

## Automation notes

- **No hook is needed for capture.** Claude Code already writes every session to `<claude.projects_dir>/<dir>/<session>.jsonl`; git, Gmail, Calendar, Drive and Slack are pulled on demand, and the phone writes straight into `inbox/`.
- **Optional SessionStart hook**: `${CLAUDE_PLUGIN_ROOT}/skills/daily-journal/scripts/open-actions.sh` prints the open actions from the latest journal as `additionalContext`, so each new session starts knowing what is pending. Wire it in `.claude/settings.json` under `hooks.SessionStart`:
  `{"matcher": "", "hooks": [{"type": "command", "command": "bash /path/to/daily-journal/plugin/skills/daily-journal/scripts/open-actions.sh"}]}`
- **Scheduling**: the collector needs the machine that has the transcripts, the `gws` keyring and the local repos, so a cloud routine cannot run it. Run `/daily-journal yesterday` in the morning, or loop it in a long-running local session at the end of the day.
- If an action should become a ticket or a board card somewhere, do that explicitly; the journal never writes to external systems.
