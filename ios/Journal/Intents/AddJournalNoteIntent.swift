import AppIntents
import JournalKit

enum CaptureKindChoice: String, AppEnum {
    case action, note

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Capture kind")
    static let caseDisplayRepresentations: [CaptureKindChoice: DisplayRepresentation] = [
        .action: "Action", .note: "Note",
    ]

    var kind: CaptureKind { self == .action ? .action : .note }
}

/// "Add to Journal" for Siri, Shortcuts and the Action button. Writes straight into the inbox folder.
struct AddJournalNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Journal"
    static let description = IntentDescription("Saves a note or action into the journal inbox for the next daily run.")
    static let openAppWhenRun = false

    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    @Parameter(title: "Kind", default: .action)
    var kind: CaptureKindChoice

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to journal as \(\.$kind)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let (url, _) = FolderAccess.resolve() else {
            throw IntentError.noFolder
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let io = JournalFileIO(root: url)
        _ = try await io.writeCapture(kind: kind.kind, body: text, device: "Shortcut")
        return .result(dialog: "Added to your journal inbox.")
    }

    enum IntentError: Error, CustomLocalizedStringResourceConvertible {
        case noFolder
        var localizedStringResource: LocalizedStringResource { "Open Journal once and choose your journal folder first." }
    }
}

struct JournalShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddJournalNoteIntent(), phrases: ["Add to \(.applicationName)", "Add a note to \(.applicationName)"],
                    shortTitle: "Add to Journal", systemImageName: "square.and.pencil")
    }
}
