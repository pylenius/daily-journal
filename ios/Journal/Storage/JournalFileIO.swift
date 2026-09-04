import CryptoKit
import Foundation
import JournalKit

/// All reads and writes to the journal folder, coordinated so iCloud and other file providers stay consistent.
actor JournalFileIO {
    struct EntryFile: Sendable {
        let url: URL
        let name: String
        let date: String
        let modified: Date?
        /// True when the provider has not downloaded the content yet.
        let isPlaceholder: Bool
    }

    struct Loaded: Sendable {
        let text: String
        let modified: Date?
        let hash: String
    }

    enum IOError: Error, LocalizedError {
        case coordination(String)
        case changedSinceLoad
        case lineNotFound
        case notADirectory

        var errorDescription: String? {
            switch self {
            case .coordination(let m): return m
            case .changedSinceLoad: return "The entry changed on another device since you opened it."
            case .lineNotFound: return "That line is no longer in the entry. It was reloaded."
            case .notADirectory: return "The chosen item is not a folder."
            }
        }
    }

    let root: URL
    private let fm = FileManager.default

    init(root: URL) { self.root = root }

    var inboxURL: URL { root.appendingPathComponent("inbox", isDirectory: true) }

    // MARK: Listing

    func listEntryFiles() throws -> [EntryFile] {
        try coordinatedRead(root) { url in
            let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey, .ubiquitousItemDownloadingStatusKey, .nameKey]
            let items = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [])
            var out: [EntryFile] = []
            for item in items {
                var name = item.lastPathComponent
                var placeholder = false
                // iCloud placeholders in a plain folder look like ".2026-09-03.md.icloud"
                if name.hasPrefix("."), name.hasSuffix(".icloud") {
                    name = String(name.dropFirst().dropLast(".icloud".count))
                    placeholder = true
                    try? fm.startDownloadingUbiquitousItem(at: item)
                }
                guard let date = JournalParser.date(fromFileName: name) else { continue }
                let values = try? item.resourceValues(forKeys: Set(keys))
                if let status = values?.ubiquitousItemDownloadingStatus, status != .current {
                    placeholder = placeholder || status == .notDownloaded
                    if status == .notDownloaded { try? fm.startDownloadingUbiquitousItem(at: item) }
                }
                out.append(EntryFile(url: placeholder ? url.appendingPathComponent(name) : item, name: name, date: date,
                                     modified: values?.contentModificationDate, isPlaceholder: placeholder))
            }
            return out.sorted { $0.date > $1.date }
        }
    }

    // MARK: Reading

    func read(_ url: URL) throws -> Loaded {
        try coordinatedRead(url) { url in
            let data = try Data(contentsOf: url)
            let text = String(decoding: data, as: UTF8.self)
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return Loaded(text: text, modified: modified, hash: JournalFileIO.hash(data))
        }
    }

    // MARK: Writing

    /// Flips one checkbox. Re-reads inside the coordinated block so a concurrent Mac write is never clobbered.
    func toggle(_ url: URL, line: Int, expectedRaw: String) throws -> Loaded {
        resolveConflicts(at: url)
        return try coordinatedWrite(url) { url in
            let data = try Data(contentsOf: url)
            let text = String(decoding: data, as: UTF8.self)
            let newText: String
            do {
                newText = try CheckboxToggler.toggle(in: text, line: line, expectedRaw: expectedRaw)
            } catch {
                throw IOError.lineNotFound
            }
            let out = Data(newText.utf8)
            try out.write(to: url, options: .atomic)
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return Loaded(text: newText, modified: modified, hash: JournalFileIO.hash(out))
        }
    }

    /// Replaces the whole file. When `expectedHash` is given and the file no longer matches it, nothing is written.
    func write(_ url: URL, text: String, expectedHash: String?) throws -> Loaded {
        resolveConflicts(at: url)
        return try coordinatedWrite(url) { url in
            if let expectedHash, let current = try? Data(contentsOf: url), JournalFileIO.hash(current) != expectedHash {
                throw IOError.changedSinceLoad
            }
            let out = Data(text.utf8)
            try out.write(to: url, options: .atomic)
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return Loaded(text: text, modified: modified, hash: JournalFileIO.hash(out))
        }
    }

    // MARK: Inbox

    func listInbox() throws -> [InboxCapture] {
        guard fm.fileExists(atPath: inboxURL.path) else { return [] }
        return try coordinatedRead(inboxURL) { url in
            let items = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            var out: [InboxCapture] = []
            for item in items where item.pathExtension == "md" {
                if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { continue }
                guard let data = try? Data(contentsOf: item) else { continue }
                out.append(InboxParser.parse(fileName: item.lastPathComponent, contents: String(decoding: data, as: UTF8.self)))
            }
            return out.sorted { $0.fileName > $1.fileName }
        }
    }

    func writeCapture(kind: CaptureKind, body: String, device: String?) throws -> String {
        let (name, contents) = InboxWriter.makeCapture(kind: kind, body: body, device: device)
        try coordinatedWrite(inboxURL, options: .forMerging) { dir in
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: dir.appendingPathComponent(name), options: .withoutOverwriting)
        }
        return name
    }

    // MARK: Conflicts

    /// Spec rule: newest body wins, a box checked in any version stays checked.
    func resolveConflicts(at url: URL) {
        guard let others = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !others.isEmpty else { return }
        var versions: [ConflictResolver.Version] = []
        if let current = try? Data(contentsOf: url) {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            versions.append(.init(modified: modified, text: String(decoding: current, as: UTF8.self)))
        }
        for v in others {
            if let u = v.url as URL?, let data = try? Data(contentsOf: u) {
                versions.append(.init(modified: v.modificationDate ?? .distantPast, text: String(decoding: data, as: UTF8.self)))
            }
        }
        let merged = ConflictResolver.merge(versions)
        try? coordinatedWrite(url) { url in
            try Data(merged.utf8).write(to: url, options: .atomic)
        }
        for v in others { v.isResolved = true }
        try? NSFileVersion.removeOtherVersionsOfItem(at: url)
    }

    // MARK: Helpers

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func coordinatedRead<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
        var coordError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordError) { u in
            result = Result { try body(u) }
        }
        if let coordError { throw IOError.coordination(coordError.localizedDescription) }
        return try result!.get()
    }

    @discardableResult
    private func coordinatedWrite<T>(_ url: URL, options: NSFileCoordinator.WritingOptions = .forReplacing, _ body: (URL) throws -> T) throws -> T {
        var coordError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: options, error: &coordError) { u in
            result = Result { try body(u) }
        }
        if let coordError { throw IOError.coordination(coordError.localizedDescription) }
        return try result!.get()
    }
}
