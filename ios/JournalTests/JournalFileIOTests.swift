import Foundation
import JournalKit
import Testing
@testable import Journal

@Suite struct JournalFileIOTests {
    static let fixture = """
    # Journal — 2026-09-03 (Thursday)

    ## Done
    - one

    ## Actions
    - [ ] first — source: a
    - [ ] second — source: b

    ## Details
    - text
    """

    func makeRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("journal-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(Self.fixture.utf8).write(to: dir.appendingPathComponent("2026-09-03.md"))
        try Data("not an entry".utf8).write(to: dir.appendingPathComponent("README.md"))
        return dir
    }

    @Test func listsReadsTogglesAndGuards() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let io = JournalFileIO(root: root)

        let files = try await io.listEntryFiles()
        #expect(files.map(\.date) == ["2026-09-03"])

        let loaded = try await io.read(files[0].url)
        let entry = JournalParser.parse(loaded.text, fileName: files[0].name)
        #expect(entry.actions.count == 2)

        let toggled = try await io.toggle(files[0].url, line: entry.actions[1].line, expectedRaw: entry.actions[1].raw)
        let onDisk = try String(contentsOf: files[0].url, encoding: .utf8)
        #expect(onDisk == toggled.text)
        #expect(onDisk.contains("- [x] second — source: b"))
        #expect(onDisk.contains("- [ ] first — source: a"))
        #expect(toggled.hash != loaded.hash)

        // stale hash → refused, file untouched
        await #expect(throws: JournalFileIO.IOError.self) {
            try await io.write(files[0].url, text: "clobber", expectedHash: loaded.hash)
        }
        #expect(try String(contentsOf: files[0].url, encoding: .utf8) == onDisk)

        // matching hash → written
        let written = try await io.write(files[0].url, text: onDisk + "\n- extra\n", expectedHash: toggled.hash)
        #expect(try String(contentsOf: files[0].url, encoding: .utf8) == written.text)

        // a line that vanished → lineNotFound
        await #expect(throws: JournalFileIO.IOError.self) {
            try await io.toggle(files[0].url, line: 3, expectedRaw: "- [ ] gone")
        }
    }

    @Test func capturesLandInInbox() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let io = JournalFileIO(root: root)
        #expect(try await io.listInbox().isEmpty)
        let name = try await io.writeCapture(kind: .action, body: "Call back", device: "Test")
        #expect(name.hasSuffix(".md"))
        let inbox = try await io.listInbox()
        #expect(inbox.count == 1)
        #expect(inbox[0].kind == .action)
        #expect(inbox[0].body == "Call back")
        #expect(inbox[0].device == "Test")
    }
}
