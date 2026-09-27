# daily-journal

A private daily work journal, written for you by Claude Code. Once a day you run `/daily-journal` and it turns the day's evidence — your git commits, your Claude Code session transcripts, your Google Calendar meetings and their Gemini notes, Gmail (received and sent), Google Docs edited that day, Slack messages and quick captures from your phone — into one Markdown file: a short **Done** list, an **Actions** checklist with a source reference on every line, the items **Carried over** from the previous day, and a **Details** section with links so anything can be picked up later. Open actions follow you from day to day until you tick them.

## The two parts

- **`plugin/`** — a Claude Code plugin with the `daily-journal` skill and its collector scripts. This is the writer: it runs on the Mac that has your repos, transcripts and `gws` login.
- **`ios/`** — an iOS app that reads the same folder from iCloud Drive: shows today's entry, lets you tick actions, and drops quick captures into `inbox/` that the next journal run folds in. See below.
- **`mac/`** — the same app for macOS, reading the journal folder directly. It shares the file, store and rendering code with `ios/`.
- **`windows/`** — the same app for Windows 10/11 (WinUI 3, .NET), for a folder synced by iCloud for Windows, OneDrive or Google Drive.
- **`android/`** — the same app for Android 10+ (Kotlin, Jetpack Compose), for a folder a sync app keeps on the phone.

Both sides follow the same file contract, `spec/JOURNAL_FORMAT.md`.

## Requirements

- [Claude Code](https://claude.com/claude-code)
- `python3` 3.11 or newer (standard library only)
- Optional: the [`gws`](https://github.com/googleworkspace/cli) CLI for Calendar, Gmail and Docs — `brew install googleworkspace/tap/gws`, then `gws auth login`. Without it those sections are skipped and the journal says so.
- Optional: a Slack MCP server with a message-search tool connected to Claude Code. Without it the journal notes "Slack: not connected".

## Install

This repository is its own Claude Code plugin marketplace. In Claude Code:

```
/plugin marketplace add pylenius/daily-journal
/plugin install daily-journal@pylenius
```

or from the shell:

```bash
claude plugin marketplace add pylenius/daily-journal
claude plugin install daily-journal@pylenius
```

Alternatively copy the skill into a project or your home directory:

```bash
cp -R plugin/skills/daily-journal ~/.claude/skills/daily-journal
```

## Configure

Create `~/.config/daily-journal/config.json` (start from `plugin/config.example.json`). Only `journal_dir` is required; the collector prints the example and exits when the file is missing. The env var `DAILY_JOURNAL_CONFIG` points it at another file.

```json
{
  "journal_dir": "~/Library/Mobile Documents/com~apple~CloudDocs/Journal",
  "timezone": "Europe/Helsinki",
  "me": { "name": "Your Name", "email": "you@example.com" },
  "git": { "roots": ["~/Coding/myOGO"], "depth": 1, "author": "Your Name" },
  "claude": { "projects_dir": "~/.claude/projects", "project_filter": [] },
  "google": {
    "enabled": true,
    "calendar_id": "primary",
    "gmail_exclude_categories": ["promotions", "updates", "social", "forums"],
    "gmail_noise_senders": ["noreply", "no-reply", "notifications@", "calendar-notification", "gemini-notes@"]
  },
  "slack": { "enabled": true, "handle": "yourhandle" }
}
```

- `journal_dir` — where the entries live. Put it in iCloud Drive if you use the iOS app. `~` expands.
- `timezone` — IANA name; day boundaries are local midnight there. Defaults to the machine's zone.
- `me.name` — matched against the assignee tags in Gemini "Next steps"; `me.email` — used to spot you in attendee lists.
- `git.roots` — directories to scan for repositories. Each root is scanned itself and one level down; `depth: 2` also looks one level deeper (children of a directory that is itself a repo are not descended into). `git.author` is passed to `git log --author`.
- `claude.projects_dir` — where Claude Code keeps transcripts. `project_filter` — if non-empty, only project directories whose name contains one of these substrings are read.
- `google.enabled` — set to `false` to skip Calendar/Gmail/Docs entirely. The category and sender lists filter noise out of Gmail.
- `slack.handle` — your Slack handle without `@`, used in the search queries.

## Run

Inside Claude Code:

- `/daily-journal` — today's entry
- `/daily-journal yesterday` — yesterday's (the usual morning run)
- `/daily-journal 2026-09-03` — a specific day; several days are processed oldest first so carry-over chains

The collector takes one to three minutes when Google sources are enabled. Claude then reads the raw material, runs the Slack searches if a tool is available, writes the entry, archives the inbox captures and shows you the Done and Actions lists.

## Where files go

```
<journal_dir>/
├── YYYY-MM-DD.md            one entry per day
└── inbox/
    ├── *.md                 captures from the phone, waiting for the next run
    └── archive/YYYY-MM/     captures already folded into an entry
```

Raw material (exported docs, the collector's `raw.md`) is written to `$TMPDIR/daily-journal/<date>/` (or Claude Code's scratchpad) and is safe to delete.

Manual inbox management: `inbox.py list` prints the pending captures as JSON, `inbox.py archive [--dry-run]` moves them to the archive without overwriting anything.

## Privacy

Journal entries contain names, customer details, figures from meeting notes and email excerpts. Treat the folder as confidential:

- Everything is written locally. Nothing leaves the machine except the queries the collector makes to **your own** Google and Slack accounts through `gws` and your Slack MCP server.
- iCloud Drive is end-to-end encrypted only when [Advanced Data Protection](https://support.apple.com/en-us/102651) is turned on for your Apple account; without it Apple holds the keys.
- The skill never publishes an entry, never pastes it into chat tools, and never commits it unless you ask.

## Optional: open actions at session start

Add a SessionStart hook so every new Claude Code session starts knowing what is pending. In `.claude/settings.json` (project or user level):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "bash /path/to/daily-journal/plugin/skills/daily-journal/scripts/open-actions.sh" }
        ]
      }
    ]
  }
}
```

The script prints the unchecked items from the latest entry's Actions and Carried over sections as additional context, and nothing when there is no journal yet.

## iOS app

`ios/` holds **Journal**, a native SwiftUI app for iPhone and iPad (iOS 18+). It works directly on the journal folder — no server, no account:

| | |
|---|---|
| ![Day list](docs/screenshots/days.png) | ![Entry](docs/screenshots/entry.png) |

- **Days** — every entry, grouped by month, with done and open-action counts.
- **Entry** — Done, Actions and Carried over as native rows (tap the circle to tick; links open in the browser; references are copyable), Details rendered as Markdown. Ticking edits the file in place: exactly one line changes, nothing is re-serialised.
- **Actions** — every open action across all days, one per action even when it was carried over for a week; ticking writes to the newest day's file, which is what the next Mac run reads.
- **Search** — every line of every entry, all words must match on the same line.
- **Inbox** — captures waiting for the next run; **+** adds a note or action as a file in `inbox/`. "Add to Journal" is also available as a Shortcut / Siri action.
- **Edit** — raw Markdown editor with a stale-file guard: if the Mac rewrote the entry while you were editing, you choose overwrite, discard or copy.

Sync is whatever the Files app provides. The app asks you to pick the journal folder once (iCloud Drive, OneDrive, Google Drive, … any provider that supports opening in place) and keeps a bookmark. Reads and writes go through file coordination; iCloud conflict versions are merged with the spec rule — newest body wins, a box ticked in any version stays ticked.

### Build

```bash
brew install xcodegen
cd ios
cp Signing.xcconfig.example Signing.xcconfig   # add your DEVELOPMENT_TEAM and a bundle id
./bootstrap.sh                                  # generates Journal.xcodeproj (git-ignored)
open Journal.xcodeproj
```

Run on the simulator or your device from Xcode. The parser and file logic live in the `ios/Packages/JournalKit` Swift package, which has no UI dependency and is tested with `swift test --package-path ios/Packages/JournalKit`. For UI work on the simulator, launch arguments `-journalFolder /path/to/folder` and `-openDate YYYY-MM-DD` skip the picker.

## Mac app

`mac/` holds **Journal** for macOS 15+. It works on the same folder as the iOS app, with the same features, in a three-column window: Days / Actions / Inbox in the sidebar, the list in the middle, the entry on the right. Search is the sidebar field; right-click a Done item to highlight or remove it, or an action to tick it or copy its reference.

Shortcuts: ⇧⌘N quick capture · ⌘T today · ⌘E edit entry · ⌘R reload · ⇧⌘O choose folder · ⌘, settings.

The Mac project has no copies of its own for the shared parts. It compiles `ios/Journal/Storage`, `Store`, `Rendering`, `Intents` and the row views directly, and uses `ios/Packages/JournalKit`. Only the window and views are Mac-specific.

```bash
cd mac
cp Signing.xcconfig.example Signing.xcconfig   # add your DEVELOPMENT_TEAM and a bundle id
./bootstrap.sh                                  # generates JournalMac.xcodeproj (git-ignored)
open JournalMac.xcodeproj
```

**Installing.** Download `Journal-<version>.dmg` from the [Releases](https://github.com/pylenius/daily-journal/releases) page, open it and drag Journal to Applications. Release builds are signed with Developer ID and notarized, so they open without warnings.

**Making a release.** `mac/release.sh` archives, signs with Developer ID, builds the DMG, notarizes and staples it into `mac/out/`; `--publish` also attaches it to a GitHub Release tagged `mac-v<version>`. One-time setup: a *Developer ID Application* certificate (Xcode → Settings → Accounts → Manage Certificates → +), notarization credentials stored with `xcrun notarytool store-credentials daily-journal-notary --apple-id <you> --team-id <TEAMID>`, and your team id as `DEVELOPMENT_TEAM` in `Signing.xcconfig`.

Release builds are sandboxed and remember the folder with a security-scoped bookmark. Debug builds run unsandboxed, so the launch arguments `-journalFolder /path/to/folder` and `-openDate YYYY-MM-DD` work there as they do on the simulator.

## Windows app

`windows/` holds **Journal** for Windows 10 and 11, x64 and ARM64. It is a WinUI 3 app on .NET 10 with the same features: **Days** (month-grouped list with the entry beside it), **Actions**, **Search**, **Inbox**, **Quick capture** and a raw **Edit** window with the same stale-file guard. Tick the box to toggle an action; right-click a Done item (or use its **…** button) to highlight or remove it. Ticking, highlighting and removing are single-line edits, exactly as on iOS.

Shortcuts: Ctrl+N quick capture · F5 / Ctrl+R reload · Ctrl+F search · Ctrl+S save in the editor.

Pick the journal folder once; it is remembered in `%LOCALAPPDATA%\DailyJournal\settings.json`. Any sync client that shows the folder on disk works: iCloud for Windows (`%USERPROFILE%\iCloudDrive\Journal`), OneDrive, Google Drive for desktop. Cloud-only files are downloaded on first read, and the folder is watched, so changes from the Mac appear on their own. Sync clients write conflicts as separately named copies (`2026-09-03-DESKTOP.md`), which the format's file-name rule ignores. Captures are written with `device: Windows`.

The format logic is a C# port of JournalKit in `windows/src/JournalCore` (plain .NET, no Windows dependency) with the same tests over the same fixtures:

```bash
dotnet test windows/tests/JournalCore.Tests          # any OS
```

**Installing.** Download `Journal-Setup-<version>.exe` from the [Releases](https://github.com/pylenius/daily-journal/releases) page and run it. One installer covers x64 and ARM64 PCs; it installs for the current user (no admin rights) with a Start menu entry and an uninstaller. Portable zips are attached too. The builds are not code-signed yet, so SmartScreen may show "Windows protected your PC" the first time: **More info → Run anyway**.

Releases are built by CI: push a tag `windows-v<version>` (e.g. `windows-v0.1.0`) and the workflow publishes the installer and zips. To build them locally on Windows, install Inno Setup (`winget install JRSoftware.InnoSetup`) and run `windows\installer\build-installer.ps1`; the files land in `windows\out\`.

The app itself builds on Windows only (.NET 10 SDK; Visual Studio is not required):

```powershell
dotnet build windows\src\Journal.App                                   # Debug, for this machine's architecture
dotnet publish windows\src\Journal.App -c Release -r win-x64 -o out    # or win-arm64
out\Journal.exe
```

The published folder is self-contained (.NET and the Windows App SDK included, about 240 MB), so it runs from a zip without an installer or signing. `--journalFolder <path>` and `--openDate YYYY-MM-DD` skip the picker, as on the other platforms. CI builds both architectures and uploads them as artifacts.

## Android app

`android/` holds **Journal** for Android 10 and newer, phones and tablets. It is a Kotlin / Jetpack Compose app with the same features: **Days**, **Actions**, **Search** and **Inbox** tabs, the entry view (tick the box to toggle an action; long-press a Done item to highlight, copy or remove it, or an action to copy its reference or open its links), the raw **Edit** screen with the same stale-file guard, and quick capture from the **+** button. Two Android extras: **Share → Add to Journal** from any app turns the shared text into a capture, and long-pressing the launcher icon offers **New capture**. Ticking, highlighting and removing are single-line edits, as everywhere else. Captures are written with `device: Android`.

**The folder.** Android has no iCloud Drive, and the Google Drive and OneDrive apps do not hand out their folders to other apps as a folder. The journal folder has to be a real folder on the phone that a sync app keeps up to date with the Mac, for example [Syncthing](https://syncthing.net) (Mac ↔ phone directly, no cloud) or FolderSync / Autosync for Google Drive, OneDrive or Dropbox. On first launch, choose that folder in the system folder picker. The app keeps the permission and reads and writes the files in place through the Storage Access Framework. It never uploads anything itself.

Android cannot watch a folder through the Storage Access Framework, so the app checks it for changes when it comes to the front and every 15 seconds while open (a cheap listing; files are read only when something changed). Pull down to reload. The Storage Access Framework cannot rename one file over another, so an edit re-reads the file and then rewrites it in place; sync conflicts come back as separately named copies, which the format's file-name rule ignores.

The format logic is a Kotlin port of JournalKit in `android/journalcore` (plain JVM, no Android dependency) with the same tests over the same fixtures:

```bash
cd android
./gradlew :journalcore:test                 # any OS with JDK 17+
./gradlew :app:assembleDebug                # needs the Android SDK (ANDROID_HOME)
adb install app/build/outputs/apk/debug/app-debug.apk
```

Or open `android/` in Android Studio. Debug builds install as `io.github.dailyjournal.journal.debug`, next to a release build, and accept `-e journalFolder <path>` (a directory the app can read, e.g. under its own `files/`) and `-e openDate YYYY-MM-DD` on `adb shell am start`, to skip the picker as on the other platforms. CI runs the tests, builds both variants and uploads the debug APK as an artifact.

**Installing.** Download `Journal-<version>.apk` from the [Releases](https://github.com/pylenius/daily-journal/releases) page on the phone and open it; Android asks once to allow installing apps from your browser or file manager. Later releases install over it as updates.

**Making a release.** Push a tag `android-v<version>` (e.g. `android-v0.1.0`) and the workflow builds a signed, minified APK (about 3 MB) and attaches it to a GitHub Release. The version code is derived from the tag (`1.2.3` → 10203), so keep minor and patch below 100. One-time setup: create an upload key and store it as repository secrets.

```bash
keytool -genkeypair -keystore journal-release.jks -alias journal -keyalg RSA -keysize 4096 -validity 10000
base64 -i journal-release.jks | gh secret set ANDROID_KEYSTORE_BASE64
gh secret set ANDROID_KEYSTORE_PASSWORD      # the store password you chose
gh secret set ANDROID_KEY_ALIAS --body journal
gh secret set ANDROID_KEY_PASSWORD           # the key password (same as the store password unless you chose another)
```

Keep the key in `android/signing/`, which is git-ignored, next to a `signing.env` that exports the four `JOURNAL_*` variables below, and back that folder up somewhere safe outside the repository. Android only installs an update signed with the same key, so losing it means uninstalling and reinstalling the app.

To build a signed APK locally, set `JOURNAL_KEYSTORE` (path), `JOURNAL_KEYSTORE_PASSWORD`, `JOURNAL_KEY_ALIAS` and `JOURNAL_KEY_PASSWORD` (`source signing/signing.env`) and run `./gradlew :app:assembleRelease -PversionName=0.1.0 -PversionCode=100`. Without them the release APK is unsigned.

## License

MIT — see `LICENSE`.
