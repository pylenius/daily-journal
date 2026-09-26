import Foundation

/// Fires `onChange` when anything in the journal folder changes: file presenter for local/provider changes,
/// metadata query for iCloud folders granted through the document picker (iOS only; on the Mac the folder is a real path).
final class FolderWatcher: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    private let onChange: @Sendable () -> Void
    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?

    init(folder: URL, onChange: @escaping @Sendable () -> Void) {
        self.presentedItemURL = folder
        self.onChange = onChange
        super.init()
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        NSFileCoordinator.addFilePresenter(self)
        #if os(iOS)
        Task { @MainActor in self.startMetadataQuery() }
        #endif
    }

    deinit {
        NSFileCoordinator.removeFilePresenter(self)
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func presentedItemDidChange() { onChange() }
    func presentedSubitemDidChange(at url: URL) { onChange() }
    func presentedSubitemDidAppear(at url: URL) { onChange() }
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { onChange() }

    @MainActor
    private func startMetadataQuery() {
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope, NSMetadataQueryUbiquitousDocumentsScope]
        q.predicate = NSPredicate(format: "%K LIKE '*.md'", NSMetadataItemFSNameKey)
        let change = onChange
        observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: q, queue: .main) { _ in change() }
        q.start()
        query = q
    }
}
