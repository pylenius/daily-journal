import Foundation
import JournalKit
import Observation
import SwiftUI

@MainActor
@Observable
final class JournalStore {
    enum FolderState: Equatable {
        case notChosen
        case ready(URL)
        case unreachable(String)
    }

    var folderState: FolderState = .notChosen
    /// Newest first.
    var entries: [JournalEntry] = []
    var placeholders: [String] = []
    var inbox: [InboxCapture] = []
    var openActions: [AggregatedAction] = []
    var index = SearchIndex(entries: [])
    var lastRefresh: Date?
    var isLoading = false
    var errorMessage: String?
    var bookmarkIsStale = false

    private(set) var hashes: [String: String] = [:]
    private var urls: [String: URL] = [:]
    private var io: JournalFileIO?
    private var watcher: FolderWatcher?
    private var reloadTask: Task<Void, Never>?
    private var accessedURL: URL?

    init() {
        // Simulator convenience: `-journalFolder /path` skips the picker and leaves the saved bookmark alone;
        // `-sampleJournal` opens a fresh sample journal (used for the App Store screenshots).
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-journalFolder"), i + 1 < args.count {
            activate(URL(fileURLWithPath: args[i + 1], isDirectory: true))
        } else if args.contains("-sampleJournal") {
            useSampleJournal()
        } else {
            restore()
        }
    }

    // MARK: Folder

    func restore() {
        guard let (url, stale) = FolderAccess.resolve() else { folderState = .notChosen; return }
        bookmarkIsStale = stale
        activate(url)
    }

    func chooseFolder(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            folderState = .unreachable("No permission to read \(url.lastPathComponent).")
            return
        }
        do { try FolderAccess.save(url) } catch {
            folderState = .unreachable("Could not remember the folder: \(error.localizedDescription)")
            return
        }
        url.stopAccessingSecurityScopedResource()
        bookmarkIsStale = false
        restore()
    }

    /// Writes the made-up sample journal into the app's Documents and opens it like a picked folder.
    func useSampleJournal() {
        do {
            let url = try SampleJournal.create()
            try FolderAccess.save(url)
            bookmarkIsStale = false
            restore()
        } catch {
            errorMessage = "Could not create the sample journal: \(error.localizedDescription)"
        }
    }

    var isSampleJournal: Bool { folderName == SampleJournal.folderName }

    func forgetFolder() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
        FolderAccess.clear()
        watcher = nil; io = nil
        entries = []; inbox = []; openActions = []; index = SearchIndex(entries: []); hashes = [:]; urls = [:]
        folderState = .notChosen
    }

    private func activate(_ url: URL) {
        accessedURL?.stopAccessingSecurityScopedResource()
        if url.startAccessingSecurityScopedResource() { accessedURL = url }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            folderState = .unreachable("The journal folder is not reachable right now.")
            return
        }
        io = JournalFileIO(root: url)
        folderState = .ready(url)
        watcher = FolderWatcher(folder: url) { [weak self] in
            Task { @MainActor in self?.scheduleReload() }
        }
        Task { await reload() }
    }

    var folderName: String {
        if case .ready(let url) = folderState { return url.lastPathComponent }
        return "—"
    }

    // MARK: Loading

    /// Debounced reload for watcher bursts.
    func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await reload()
        }
    }

    func reload() async {
        guard let io else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let files = try await io.listEntryFiles()
            var newEntries: [JournalEntry] = []
            var newHashes: [String: String] = [:]
            var newURLs: [String: URL] = [:]
            var newPlaceholders: [String] = []
            for f in files {
                newURLs[f.date] = f.url
                if f.isPlaceholder { newPlaceholders.append(f.date); continue }
                do {
                    let loaded = try await io.read(f.url)
                    if let old = hashes[f.date], old == loaded.hash, let existing = entries.first(where: { $0.date == f.date }) {
                        newEntries.append(existing)
                    } else {
                        newEntries.append(JournalParser.parse(loaded.text, fileName: f.name))
                    }
                    newHashes[f.date] = loaded.hash
                } catch {
                    newPlaceholders.append(f.date)
                }
            }
            entries = newEntries.sorted { $0.date > $1.date }
            hashes = newHashes
            urls = newURLs
            placeholders = newPlaceholders
            inbox = (try? await io.listInbox()) ?? []
            rebuildDerived()
            lastRefresh = Date()
            if case .unreachable = folderState, let root = io.root as URL? { folderState = .ready(root) }
        } catch {
            errorMessage = error.localizedDescription
            folderState = .unreachable(error.localizedDescription)
        }
    }

    private func rebuildDerived() {
        openActions = OpenActionsAggregator.openActions(entries)
        index = SearchIndex(entries: entries)
    }

    func entry(for date: String) -> JournalEntry? { entries.first { $0.date == date } }

    // MARK: Mutations

    func toggle(_ cb: CheckboxLine) async {
        guard let io, let url = urls[cb.date] else { return }
        do {
            let loaded = try await io.toggle(url, line: cb.line, expectedRaw: cb.raw)
            apply(loaded, date: cb.date, fileName: url.lastPathComponent)
        } catch {
            errorMessage = error.localizedDescription
            await reload()
        }
    }

    func remove(_ item: DoneItem) async {
        await edit(date: item.date, line: item.line, raw: item.raw, replacement: nil)
    }

    func toggleHighlight(_ item: DoneItem) async {
        guard let replacement = LineEditor.highlightToggled(item.raw) else { return }
        await edit(date: item.date, line: item.line, raw: item.raw, replacement: replacement)
    }

    private func edit(date: String, line: Int, raw: String, replacement: String?) async {
        guard let io, let url = urls[date] else { return }
        do {
            let loaded = try await io.editLine(url, line: line, expectedRaw: raw, replacement: replacement)
            apply(loaded, date: date, fileName: url.lastPathComponent)
        } catch {
            errorMessage = error.localizedDescription
            await reload()
        }
    }

    /// Full-text save. Throws `JournalFileIO.IOError.changedSinceLoad` when the file moved on.
    func save(date: String, text: String, expectedHash: String?) async throws {
        guard let io, let url = urls[date] else { return }
        let loaded = try await io.write(url, text: text, expectedHash: expectedHash)
        apply(loaded, date: date, fileName: url.lastPathComponent)
    }

    func capture(kind: CaptureKind, body: String) async {
        guard let io else { return }
        do {
            _ = try await io.writeCapture(kind: kind, body: body, device: JournalStore.deviceName)
            inbox = (try? await io.listInbox()) ?? inbox
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ loaded: JournalFileIO.Loaded, date: String, fileName: String) {
        let entry = JournalParser.parse(loaded.text, fileName: fileName)
        hashes[date] = loaded.hash
        if let i = entries.firstIndex(where: { $0.date == date }) { entries[i] = entry } else { entries.append(entry); entries.sort { $0.date > $1.date } }
        rebuildDerived()
    }

    static var deviceName: String {
        #if os(iOS)
        return UIDevice.current.model
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }
}
