import Foundation
import Observation
import UIKit

@Observable
final class FileSwipeViewModel {
    private let scanner = FileScanner()
    private let thumbnailService = FileThumbnailService()
    private let bookmarkStore = FolderBookmarkStore()
    private let downloadService = ICloudDownloadService()
    
    private static let sortOrderDefaultsKey = "preferredFileSortOrder"
    private static let autoDownloadDefaultsKey = "autoDownloadICloudFiles"   // NEU

    // Bleibt für die GESAMTE Session offen (nicht nur während des Scans) —
    // sonst verlieren spätere iCloud-Downloads/Thumbnails den Zugriff,
    // sobald der Scan seinen eigenen start/stop-Block verlassen hat.
    private var activeFolderURL: URL?

    // Komplette, ungefilterte Liste — bleibt stabil, damit Filter/Sortierung
    // jederzeit ohne erneuten Scan neu angewendet werden können.
    private var allFiles: [FileItem] = []
    private var sessionSkippedIds: [URL] = []

    var remainingFiles: [FileItem] = []
    var isScanning = false
    var scannedCount = 0

    var filter: FileFilter = .all { didSet { applyFilterAndSort() } }
    var sortOrder: FileSortOrder = .newest {
        didSet {
            applyFilterAndSort()
            UserDefaults.standard.set(sortOrder.rawValue, forKey: Self.sortOrderDefaultsKey)
        }
    }

    // NEU: steuert, ob iCloud-Only-Dateien beim Prefetch automatisch
    // heruntergeladen werden, oder ob der Nutzer das pro Datei manuell antippen muss
    var autoDownloadICloudEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(autoDownloadICloudEnabled, forKey: Self.autoDownloadDefaultsKey)
        }
    }

    // Für die Vorschau-Karten — key ist die URL, damit mehrere Karten
    // gleichzeitig im Cache liegen können (aktuelle + Prefetch).
    var thumbnails: [URL: UIImage] = [:]

    // Zusammenfassung am Ende
    private(set) var keptCount = 0
    private(set) var deletedCount = 0
    private(set) var freedBytes: Int64 = 0

    // NEU — fehlte, wird aber in delete()/confirmQueuedDeletion()/
    // restoreQueuedItem()/undoLast() vorausgesetzt
    var deleteQueue: [FileItem] = []

    private enum ReversibleAction {
        case keep(FileItem)
        case skip(FileItem)
        case delete(FileItem)
    }
    private var lastReversibleAction: ReversibleAction?

    // NEU — damit FileSwipeTab den Undo-Button disablen kann, ohne
    // lastReversibleAction selbst nach außen zu geben (bleibt private)
    var canUndo: Bool { lastReversibleAction != nil }

    var currentFile: FileItem? { remainingFiles.first }
    var nextFile: FileItem? { remainingFiles.count > 1 ? remainingFiles[1] : nil }

    // NEU: Initializer, der die gespeicherte Sortier-Präferenz lädt
    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.sortOrderDefaultsKey),
           let saved = FileSortOrder(rawValue: raw) {
            sortOrder = saved
        }
        // NEU: Default true, falls noch nie gesetzt (object(forKey:) prüft
        // explizit auf "existiert der Key überhaupt", bool(forKey:) würde bei
        // fehlendem Key fälschlich false liefern)
        if UserDefaults.standard.object(forKey: Self.autoDownloadDefaultsKey) != nil {
            autoDownloadICloudEnabled = UserDefaults.standard.bool(forKey: Self.autoDownloadDefaultsKey)
        }
    }

    func openFolder(url: URL) {
        // url kommt bereits mit aktivem Scope aus FolderPicker.
        activateFolderAccess(url)
        try? bookmarkStore.save(url: url)
        startScan(folder: url)
    }

    func resumeLastFolder() -> Bool {
        guard let url = try? bookmarkStore.resolve() else { return false }
        // Nach resolve() ist noch KEIN Zugriff aktiv — muss explizit
        // gestartet werden, sonst schlägt jeder Dateizugriff still fehl.
        guard url.startAccessingSecurityScopedResource() else { return false }
        activateFolderAccess(url)
        startScan(folder: url)
        return true
    }

    private func activateFolderAccess(_ url: URL) {
        if let previous = activeFolderURL, previous != url {
            previous.stopAccessingSecurityScopedResource()
        }
        activeFolderURL = url
    }

    deinit {
        activeFolderURL?.stopAccessingSecurityScopedResource()
    }

    private func startScan(folder: URL) {
        allFiles = []
        remainingFiles = []
        scannedCount = 0
        isScanning = true

        Task {
            await scanner.scan(
                folder: folder,
                onBatch: { [weak self] batch in
                    guard let self else { return }
                    self.allFiles.append(contentsOf: batch)
                    self.scannedCount = self.allFiles.count
                    // Progressiv befüllen statt auf den kompletten Scan zu
                    // warten — bei großen iCloud-Ordnern spürbar schneller
                    // "nutzbar", auch wenn der Scan im Hintergrund weiterläuft.
                    self.applyFilterAndSort()
                },
                onComplete: { [weak self] _ in
                    self?.isScanning = false
                }
            )
        }
    }

    private func applyFilterAndSort() {
        let filtered = allFiles.filter { filter.matches($0.contentType) }
        let skippedSet = Set(sessionSkippedIds)
        let sorted = sortOrder.sort(filtered)
        remainingFiles = sorted.filter { !skippedSet.contains($0.url) }
            + sorted.filter { skippedSet.contains($0.url) }
        prefetchUpcoming()
    }

    // MARK: - Aktionen

    func keep() {
        guard let item = currentFile else { return }
        keptCount += 1
        lastReversibleAction = .keep(item)
        advance()
    }

    func skipForNow() {
        guard let item = currentFile else { return }
        sessionSkippedIds.append(item.url)
        lastReversibleAction = .skip(item)
        advance()
    }

    func delete() {
        guard let item = currentFile else { return }
        deleteQueue.append(item)
        lastReversibleAction = .delete(item)
        advance()
    }

    // Wird vom FileDeleteConfirmSheet pro Datei beim finalen "Jetzt löschen" aufgerufen
    func confirmQueuedDeletion(_ item: FileItem) {
        try? FileManager.default.removeItem(at: item.url)
        deletedCount += 1
        freedBytes += item.size
        allFiles.removeAll { $0.url == item.url }
        deleteQueue.removeAll { $0.url == item.url }
        clearReversibleActionIfMatches(item.url)
    }

    func restoreQueuedItem(_ item: FileItem) {
        deleteQueue.removeAll { $0.url == item.url }
        remainingFiles.insert(item, at: 0)
        clearReversibleActionIfMatches(item.url)
    }

    private func clearReversibleActionIfMatches(_ url: URL) {
        if case .delete(let item) = lastReversibleAction, item.url == url {
            lastReversibleAction = nil
        }
    }

    // Fürs Review-Grid: Thumbnails der wartenden Dateien sind meist schon im
    // Cache (die Karte wurde ja vorher gezeigt) — nur im Ausnahmefall (sehr
    // schnell geswiped) neu laden. thumbnailService bleibt dadurch privat,
    // FileDeleteConfirmSheet braucht keinen eigenen Zugriff darauf.
    func thumbnail(for item: FileItem) async -> UIImage? {
        if let cached = thumbnails[item.url] { return cached }
        let image = await thumbnailService.thumbnail(for: item.url, size: CGSize(width: 200, height: 200))
        if let image { thumbnails[item.url] = image }
        return image
    }

    func undoLast() {
        guard let action = lastReversibleAction else { return }
        switch action {
        case .keep(let item):
            keptCount -= 1
            remainingFiles.insert(item, at: 0)
        case .skip(let item):
            sessionSkippedIds.removeAll { $0 == item.url }
            remainingFiles.insert(item, at: 0)
        case .delete(let item):
            deleteQueue.removeAll { $0.url == item.url }
            remainingFiles.insert(item, at: 0)
        }
        lastReversibleAction = nil
    }

    // NEU: Reset aller Datei-Statistiken und Warteschlangen
    func resetAll() {
        keptCount = 0
        deletedCount = 0
        freedBytes = 0
        deleteQueue.removeAll()
        sessionSkippedIds.removeAll()
        lastReversibleAction = nil
        // Baut remainingFiles aus allFiles neu auf — vorher "behaltene" Dateien
        // (die nur aus remainingFiles entfernt wurden, nicht aus allFiles) tauchen
        // dadurch wieder in der Warteschlange auf. Bereits echt gelöschte Dateien
        // bleiben natürlich weg (allFiles wurde bei confirmQueuedDeletion() bereits
        // bereinigt) — deletedCount/freedBytes sind hier reine Statistik-Reset,
        // kein Undo der tatsächlichen Löschung.
        applyFilterAndSort()
    }

    private func advance() {
        guard !remainingFiles.isEmpty else { return }
        remainingFiles.removeFirst()
        prefetchUpcoming()
    }

    // MARK: - Thumbnails: aktuelle + nächste 2 vorladen, alte verwerfen

    // NEU: verhindert, dass für dieselbe URL mehrfach parallel ein
    // Download+Poll-Loop gestartet wird (passiert sonst, weil
    // applyFilterAndSort() während des Scans bei jedem Batch erneut
    // prefetchUpcoming() aufruft).
    private var inFlightDownloads: Set<URL> = []

    private func prefetchUpcoming() {
        let upcoming = remainingFiles.prefix(3)
        for item in upcoming {
            guard thumbnails[item.url] == nil else { continue }
            guard item.iCloudStatus != .downloadFailed else { continue }
            loadThumbnail(for: item)
        }
    }

    // NEU: greift jetzt auch bei .needsDownload (deaktivierter Auto-Download),
    // nicht mehr nur bei .downloadFailed — forceDownload umgeht den Auto-Download-Guard
    func retryDownload(for item: FileItem) {
        guard item.iCloudStatus == .downloadFailed || item.iCloudStatus == .needsDownload else { return }
        if item.iCloudStatus == .downloadFailed {
            updateICloudStatus(for: item.url, to: .needsDownload)
        }
        loadThumbnail(for: item, forceDownload: true)
    }

    private func loadThumbnail(for item: FileItem, forceDownload: Bool = false) {
        if item.iCloudStatus == .needsDownload {
            // NEU: bei deaktiviertem Auto-Download nicht selbstständig laden —
            // Karte bleibt im "needsDownload"-Zustand, bis der Nutzer manuell antippt
            guard forceDownload || autoDownloadICloudEnabled else { return }
            guard !inFlightDownloads.contains(item.url) else { return }
            inFlightDownloads.insert(item.url)
        }

        Task {
            if item.iCloudStatus == .needsDownload {
                defer { inFlightDownloads.remove(item.url) }
                do {
                    try await downloadService.ensureDownloaded(url: item.url)
                    updateICloudStatus(for: item.url, to: .downloaded)
                } catch {
                    updateICloudStatus(for: item.url, to: .downloadFailed)
                    return
                }
            }

            let image = await thumbnailService.thumbnail(for: item.url, size: CGSize(width: 800, height: 1200))
            guard remainingFiles.prefix(3).contains(where: { $0.url == item.url }) else { return }
            thumbnails[item.url] = image
        }
    }

    // Aktualisiert den iCloud-Status an der jeweiligen URL in beiden Arrays,
    // damit FileCardView den Ladeindikator sofort ausblendet, sobald der
    // Download fertig ist — ohne einen kompletten Re-Scan auszulösen.
    private func updateICloudStatus(for url: URL, to status: FileItem.ICloudStatus) {
        let url = url.standardizedFileURL
        if let idx = allFiles.firstIndex(where: { $0.url == url }) {
            let old = allFiles[idx]
            allFiles[idx] = FileItem(id: old.id, url: old.url, name: old.name, size: old.size, modifiedDate: old.modifiedDate, contentType: old.contentType, iCloudStatus: status)
        }
        if let idx = remainingFiles.firstIndex(where: { $0.url == url }) {
            let old = remainingFiles[idx]
            remainingFiles[idx] = FileItem(id: old.id, url: old.url, name: old.name, size: old.size, modifiedDate: old.modifiedDate, contentType: old.contentType, iCloudStatus: status)
        }
    }
}
