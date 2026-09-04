import Foundation

/// Remembers the journal folder the user picked, as a security-scoped bookmark.
enum FolderAccess {
    private static let key = "journalFolderBookmark"

    static func save(_ url: URL) throws {
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Resolves the stored bookmark. `stale` means the user should re-pick the folder soon.
    static func resolve() -> (url: URL, stale: Bool)? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        return (url, stale)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
