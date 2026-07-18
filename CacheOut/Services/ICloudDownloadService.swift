import Foundation

// Stößt den Download einer iCloud-Only-Datei an und wartet (mit Timeout),
// bis sie lokal verfügbar ist. Bewusst Polling statt NSMetadataQuery — wir
// beobachten immer nur EINE bekannte URL zu einem bestimmten Zeitpunkt,
// dafür ist ein dauerhaft laufender Query-Observer unnötig schwer.
actor ICloudDownloadService {
    enum DownloadError: Error {
        case timeout
    }

    func ensureDownloaded(
        url: URL,
        pollInterval: Duration = .milliseconds(300),
        timeout: Duration = .seconds(30)
    ) async throws {
        try FileManager.default.startDownloadingUbiquitousItem(at: url)

        let start = ContinuousClock.now
        while true {
            if try isDownloaded(url: url) { return }
            if ContinuousClock.now - start > timeout {
                throw DownloadError.timeout
            }
            try await Task.sleep(for: pollInterval)
        }
    }

    private func isDownloaded(url: URL) throws -> Bool {
                // WICHTIG: URL cached resourceValues intern. Ohne dieses Invalidieren
                // liefert jeder weitere Call im Poll-Loop den Status vom ALLERERSTEN
                // Aufruf zurück (meist .notDownloaded direkt nach dem Start des
                // Downloads) — der Loop läuft dann blind in den Timeout, egal ob
                // die Datei längst fertig ist.
                var url = url
                url.removeAllCachedResourceValues()
                let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                // .current oder .downloaded reichen beide — wir wollen nur wissen,
                // ob die Datei lokal lesbar ist, nicht ob es die neueste Version ist.
                let status = values.ubiquitousItemDownloadingStatus
                return status == .current || status == .downloaded
            }
}
