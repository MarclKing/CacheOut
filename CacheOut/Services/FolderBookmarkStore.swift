import Foundation

// Verwaltet genau EIN Security-Scoped Bookmark (der zuletzt gewählte Ordner).
// Erweiterbar auf mehrere Ordner später, falls gewünscht.
final class FolderBookmarkStore {
    private let defaultsKey = "fileSwipe.folderBookmark"

    func save(url: URL) throws {
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    // Gibt nil zurück, wenn noch nie ein Ordner gewählt wurde.
    // Wirft, wenn das Bookmark komplett kaputt ist (Ordner gelöscht/entzogen).
    func resolve() throws -> URL? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale {
            // Kein Fehler, aber Ticket erneuern, damit es nicht beim
            // nächsten Mal wirklich bricht.
            try? save(url: url)
        }
        return url
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
