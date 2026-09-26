import Foundation

/// Remembers the journal folder the user picked, as a security-scoped bookmark.
enum FolderAccess {
    private static let key = "journalFolderBookmark"

    // The Mac sandbox only honours a bookmark across launches when it is security-scoped.
    #if os(macOS)
    private static let createOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
    private static let resolveOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    private static let createOptions: URL.BookmarkCreationOptions = []
    private static let resolveOptions: URL.BookmarkResolutionOptions = []
    #endif

    static func save(_ url: URL) throws {
        let data = try url.bookmarkData(options: createOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Resolves the stored bookmark. `stale` means the user should re-pick the folder soon.
    static func resolve() -> (url: URL, stale: Bool)? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: resolveOptions, relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        return (url, stale)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
