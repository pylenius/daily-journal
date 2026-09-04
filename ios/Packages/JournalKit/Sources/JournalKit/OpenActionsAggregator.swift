import Foundation

/// One action as seen across days: the newest copy decides its state.
public struct AggregatedAction: Sendable, Hashable, Identifiable {
    public var id: String { key }
    public let key: String
    /// The copy from the newest entry.
    public let latest: CheckboxLine
    /// Dates where the action appears, oldest first.
    public let seenOn: [String]

    public var isOpen: Bool { !latest.isChecked }
    public var firstSeen: String { seenOn.first ?? latest.date }
}

public enum OpenActionsAggregator {
    /// All actions from `## Actions` / `## Carried over`, one per identity key, newest copy wins.
    public static func aggregate(_ entries: [JournalEntry]) -> [AggregatedAction] {
        var byKey: [String: (latest: CheckboxLine, dates: Set<String>)] = [:]
        for entry in entries {
            for cb in entry.actions {
                if var existing = byKey[cb.identityKey] {
                    existing.dates.insert(cb.date)
                    if cb.date > existing.latest.date || (cb.date == existing.latest.date && cb.line > existing.latest.line) {
                        existing.latest = cb
                    }
                    byKey[cb.identityKey] = existing
                } else {
                    byKey[cb.identityKey] = (cb, [cb.date])
                }
            }
        }
        return byKey.map { AggregatedAction(key: $0.key, latest: $0.value.latest, seenOn: $0.value.dates.sorted()) }
            .sorted { a, b in
                if a.latest.date != b.latest.date { return a.latest.date > b.latest.date }
                return a.latest.line < b.latest.line
            }
    }

    /// Only the open ones, newest day first, file order within a day.
    public static func openActions(_ entries: [JournalEntry]) -> [AggregatedAction] {
        aggregate(entries).filter(\.isOpen)
    }
}
