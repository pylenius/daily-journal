import Foundation

public enum CaptureKind: String, Sendable, CaseIterable, Codable {
    case note
    case action
}

/// A capture file in `inbox/`, written by a phone and consumed by the Mac.
public struct InboxCapture: Sendable, Hashable, Identifiable {
    public var id: String { fileName }
    public let fileName: String
    public let kind: CaptureKind
    public let created: Date?
    public let device: String?
    public let body: String

    public init(fileName: String, kind: CaptureKind, created: Date?, device: String?, body: String) {
        self.fileName = fileName; self.kind = kind; self.created = created; self.device = device; self.body = body
    }
}

public enum InboxWriter {
    static let stampFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd-HHmmss"; return f
    }()

    /// File name and contents for a new capture, per spec "Inbox captures".
    public static func makeCapture(kind: CaptureKind, body: String, device: String?, now: Date = Date(),
                                   timeZone: TimeZone = .current,
                                   random: () -> UInt16 = { UInt16.random(in: 0...0xFFFF) }) -> (fileName: String, contents: String) {
        let f = stampFormatter.copy() as! DateFormatter
        f.timeZone = timeZone
        let stamp = f.string(from: now)
        let suffix = String(format: "%04x", random())
        let iso = ISO8601DateFormatter()
        iso.timeZone = timeZone
        iso.formatOptions = [.withInternetDateTime]
        var header = "kind: \(kind.rawValue)\ncreated: \(iso.string(from: now))\n"
        if let device, !device.isEmpty { header += "device: \(device)\n" }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return ("\(stamp)-\(suffix).md", header + "\n" + trimmed + "\n")
    }
}

public enum InboxParser {
    /// Parses a capture file. Unknown header keys are ignored; missing `kind` means `note`.
    public static func parse(fileName: String, contents: String) -> InboxCapture {
        let normalised = contents.replacingOccurrences(of: "\r\n", with: "\n")
        let parts = normalised.components(separatedBy: "\n\n")
        var headers: [String: String] = [:]
        var body = normalised
        let candidate = parts.first ?? ""
        let headerLines = candidate.split(separator: "\n", omittingEmptySubsequences: false)
        let looksLikeHeader = !headerLines.isEmpty && headerLines.allSatisfy { line in
            guard let colon = line.firstIndex(of: ":") else { return false }
            let key = line[..<colon]
            return !key.isEmpty && key.allSatisfy { $0.isLetter || $0 == "_" || $0 == "-" }
        }
        if looksLikeHeader {
            for line in headerLines {
                let colon = line.firstIndex(of: ":")!
                headers[String(line[..<colon]).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            body = parts.dropFirst().joined(separator: "\n\n")
        }
        let kind = headers["kind"].flatMap(CaptureKind.init(rawValue:)) ?? .note
        let created = headers["created"].flatMap { ISO8601DateFormatter().date(from: $0) }
        return InboxCapture(fileName: fileName, kind: kind, created: created, device: headers["device"],
                            body: body.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
