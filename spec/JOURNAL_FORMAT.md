# Journal file format

This is the contract between the writer (the Claude Code plugin on a Mac) and the readers (the iOS app, later Android). Both sides must follow it; anything not described here is free-form Markdown that readers pass through untouched.

## Folder layout

```
<Journal>/
├── YYYY-MM-DD.md            one entry per day
├── inbox/                   captures from the phone, waiting for the next journal run
│   ├── YYYY-MM-DD-HHmmss-xxxx.md
│   └── archive/YYYY-MM/     captures that have been folded into a journal entry
└── (anything else is ignored by readers)
```

- Entry file name: `YYYY-MM-DD.md` (ISO date, local day of the writer). Readers ignore files that do not match `^\d{4}-\d{2}-\d{2}\.md$`.
- Encoding UTF-8, LF line endings preferred. Readers must tolerate CRLF and preserve whatever the file uses when they write.
- No YAML front matter. Everything is derived from the file name and headings.

## Entry skeleton

```markdown
# Journal — YYYY-MM-DD (Weekday)

## Done
- one line per thing that changed state that day

## Actions
- [ ] text — source: <ref>
- [ ] text — source: <ref>

## Carried over
- [ ] text (from YYYY-MM-DD)
- [x] text — done: <note>

## Details

### Meetings
### Code & Claude Code sessions
### Email
### Slack
### Other projects
### Sources & gaps
```

Rules:

1. The first line is a level-1 heading. Readers take the date from the file name, not the title.
2. Level-2 headings `## Done`, `## Actions`, `## Carried over`, `## Details` are recognised by name (case-insensitive, surrounding whitespace ignored). Any other `##` heading is an ordinary section. Missing sections are allowed.
3. `## Details` may contain any Markdown, typically `###` subsections. Readers render it; they do not interpret it.
4. A section ends at the next `##` heading or end of file.

## Checkbox lines

A checkbox line matches, anywhere in the file:

```
^(\s*)- \[( |x|X)\] (.*)$
```

- `[ ]` is open, `[x]`/`[X]` is done.
- Text after `] ` up to the first ` — source:` or ` — done:` marker is the **action text**. The marker and the rest of the line is the **reference** (a URL, a Gmail id, a commit hash, a session id, free text). Readers render URLs inside the reference as links.
- Lines indented under a checkbox line (more leading whitespace, not starting with `- [`) are continuation of that item and are displayed with it.
- Readers toggle a checkbox by replacing exactly `[ ]` with `[x]` (or the reverse) on that one line. No other byte in the file changes. Readers never re-serialise Markdown when toggling.
- Only checkbox lines inside `## Actions` and `## Carried over` count as **actions**. Checkbox lines elsewhere (e.g. in Details) are rendered and may be toggled, but they are not listed as open actions.

## Action identity across days

The writer copies still-open actions into the next day's `## Carried over` section. To show one item, not one per day, readers compute an **identity key**:

1. take the action text (before the ` — source:` / ` — done:` marker)
2. remove a trailing `(from YYYY-MM-DD)` note
3. collapse whitespace, trim, lowercase, strip trailing `.`/`;`/`:`

Items with the same key are the same action. **The newest file's copy wins**: its checked state is the state, and toggling it writes to that newest file. The writer, when it reads yesterday's `## Actions` and `## Carried over`, treats any `[x]` as done and does not carry it forward.

## Inbox captures

One file per capture, written by the phone:

```
inbox/YYYY-MM-DD-HHmmss-xxxx.md      (local time of the device, xxxx = 4 random hex chars)
```

Contents:

```
kind: action          (or: note)
created: 2026-09-04T09:12:33+03:00
device: iPhone        (optional, free text)

<body: one or more lines; may contain Markdown and URLs>
```

- Header lines are `key: value`, terminated by the first empty line. Unknown keys are ignored. `kind` defaults to `note` when missing.
- The writer includes every file in `inbox/` (not `archive/`) in the next journal run: `action` captures become `- [ ] <body> — source: <device> <created>` lines under `## Actions`; `note` captures are folded into `## Done` or `## Details` as the writer sees fit. After the entry is written, the writer moves the files to `inbox/archive/YYYY-MM/` (month of the capture).
- Readers list files still in `inbox/` as **pending**. They must never delete or move inbox files; only the writer archives.

## Concurrency

- The writer replaces a whole file atomically (write temp, rename). Readers write atomically too.
- A reader that wants to toggle re-reads the file immediately before writing, locates the line by exact text (falling back to a search within the same section), and gives up with an error if the line is gone.
- If the sync provider produces conflict versions of an entry, the resolution rule is: newest body wins, but a checkbox that is `[x]` in **any** version stays `[x]`.

## Versioning

This is format version 1. A future breaking change adds a `<!-- journal-format: 2 -->` comment on line 2; readers without support show the file as plain text.
