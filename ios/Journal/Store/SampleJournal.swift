import Foundation

/// A small, made-up journal that shows what the app does before you have one of your own: three days relative to
/// today, with carried-over actions, a closed one, details and a pending inbox capture. Written as ordinary files, so
/// ticking and capturing work on it exactly as on a real journal.
enum SampleJournal {
    static let folderName = "Sample Journal"

    /// `<Documents>/Sample Journal`, recreated from scratch.
    static func create(today: Date = Date(), calendar: Calendar = .current) throws -> URL {
        let fm = FileManager.default
        let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = docs.appendingPathComponent(folderName, isDirectory: true)
        if fm.fileExists(atPath: folder.path) { try fm.removeItem(at: folder) }
        try fm.createDirectory(at: folder.appendingPathComponent("inbox", isDirectory: true), withIntermediateDirectories: true)

        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        let iso = DateFormatter()
        iso.calendar = Calendar(identifier: .gregorian)
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.timeZone = calendar.timeZone
        iso.dateFormat = "yyyy-MM-dd"
        let weekday = DateFormatter()
        weekday.locale = Locale(identifier: "en_US_POSIX")
        weekday.timeZone = calendar.timeZone
        weekday.dateFormat = "EEEE"

        let d2 = iso.string(from: day(-2)), d1 = iso.string(from: day(-1)), d0 = iso.string(from: today)
        let entries = [
            (d2, entry2(date: d2, weekday: weekday.string(from: day(-2)))),
            (d1, entry1(date: d1, weekday: weekday.string(from: day(-1)), from: d2)),
            (d0, entry0(date: d0, weekday: weekday.string(from: today), from2: d2, from1: d1)),
        ]
        for (date, text) in entries {
            try Data(text.utf8).write(to: folder.appendingPathComponent("\(date).md"), options: .atomic)
        }

        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.timeZone = calendar.timeZone
        stamp.dateFormat = "yyyy-MM-dd-HHmmss"
        let created = ISO8601DateFormatter()
        created.timeZone = calendar.timeZone
        created.formatOptions = [.withInternetDateTime]
        let capture = "kind: action\ncreated: \(created.string(from: today))\ndevice: iPhone\n\nAsk Noor for the new label printer quote\n"
        try Data(capture.utf8).write(to: folder.appendingPathComponent("inbox/\(stamp.string(from: today))-5a3e.md"), options: .atomic)
        return folder
    }

    private static func entry2(date: String, weekday: String) -> String {
        """
        # Journal — \(date) (\(weekday))

        ## Done
        - Shipped the new returns page to production after review with Sam.
        - Planning meeting: agreed to move the warehouse migration to next month.
        - Answered Alex's question about the invoice export format.

        ## Actions
        - [ ] Send Dana the updated price list — source: mail "Price list 2026" from Dana
        - [ ] Review Robin's pull request for the search filters — source: https://github.com/example/shop/pull/42
        - [ ] Book the follow-up call with the logistics partner — source: planning meeting notes, next steps

        ## Carried over
        _(first entry in the sample, nothing to carry over)_

        ## Details

        ### Meetings
        - **09:30 Planning** (Sam, Robin, Alex). Warehouse migration moves to next month; Sam owns the timeline.
        - **14:00 Partner call** with the logistics partner. They will share the new pickup point API next week.

        ### Code & AI sessions
        - Returns page: 6 commits, merged and deployed. The AI session ended with a clean test run.

        ### Sources & gaps
        - This is a sample journal. Every name and event in it is made up.
        """
    }

    private static func entry1(date: String, weekday: String, from: String) -> String {
        """
        # Journal — \(date) (\(weekday))

        ## Done
        - **Signed the logistics partner contract.**
        - Reviewed and approved Robin's search filter changes.
        - Wrote the first draft of the Q4 roadmap.

        ## Actions
        - [ ] Reply to Chris about the UK return options — source: Slack #sales, "any update on UK returns?"
        - [ ] Push the roadmap draft to the team folder — source: AI session ended with the draft unsaved

        ## Carried over
        - [x] Review Robin's pull request for the search filters (from \(from)) — done: approved, merged
        - [ ] Send Dana the updated price list (from \(from))
        - [ ] Book the follow-up call with the logistics partner (from \(from))

        ## Details

        ### Meetings
        - **11:00 Contract review** with the logistics partner. Signed; go-live target is the first of next month.

        ### Email
        - Dana asked again about the price list. Still waiting for the final numbers from finance.

        ### Sources & gaps
        - This is a sample journal. Every name and event in it is made up.
        """
    }

    private static func entry0(date: String, weekday: String, from2: String, from1: String) -> String {
        """
        # Journal — \(date) (\(weekday))

        ## Done
        - Sent Dana the updated price list.
        - Pushed the Q4 roadmap draft to the team folder.

        ## Actions
        - [ ] Prepare the demo for Thursday's customer meeting — source: calendar invite "Customer demo"
        - [ ] Check why the nightly import took twice as long — source: AI session, investigation unfinished

        ## Carried over
        - [x] Send Dana the updated price list (from \(from2)) — done: sent 10:15
        - [x] Push the roadmap draft to the team folder (from \(from1)) — done: pushed
        - [ ] Reply to Chris about the UK return options (from \(from1))
        - [ ] Book the follow-up call with the logistics partner (from \(from2))

        ## Details

        ### How this journal works
        - Each day is one Markdown file. **Done** is what changed that day, **Actions** is what waits on you, with a source for each, and **Carried over** repeats every open action until you tick it.
        - Tap a circle to tick an action; the app changes that one line in the file. Tap **+** to jot down a note or an action; it lands in the inbox for the next journal run.
        - In real use, an AI assistant writes these files every morning from your commits, meetings, mail and chats. See https://github.com/pylenius/daily-journal

        ### Sources & gaps
        - This is a sample journal. Every name and event in it is made up.
        """
    }
}
