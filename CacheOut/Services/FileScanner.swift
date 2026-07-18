import Foundation
import UniformTypeIdentifiers

// Scannt einen Ordner rekursiv, OHNE den Main Thread zu blockieren.
// Liefert Ergebnisse in Batches (onBatch), damit die UI progressiv
// befüllt werden kann statt auf das komplette Ergebnis zu warten —
// bei 10.000+ Dateien in einem iCloud-Ordner sonst spürbar Wartezeit.
actor FileScanner {
    private var currentScanTask: Task<Void, Never>?

    func scan(
        folder: URL,
        batchSize: Int = 200,
        onBatch: @escaping ([FileItem]) -> Void,
        onComplete: @escaping (Int) -> Void
    ) {
        currentScanTask?.cancel()
        currentScanTask = Task {
            guard folder.startAccessingSecurityScopedResource() else { return }
            defer { folder.stopAccessingSecurityScopedResource() }

            let keys: [URLResourceKey] = [
                .fileSizeKey, .contentModificationDateKey, .contentTypeKey,
                .ubiquitousItemDownloadingStatusKey, .isDirectoryKey
            ]
            guard let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else { onComplete(0); return }

            var batch: [FileItem] = []
            var total = 0

            // FIX 1: while-Loop mit nextObject() statt for-in über enumerator
            while let object = enumerator.nextObject() {
                if Task.isCancelled { return }
                guard let url = object as? URL else { continue }
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isDirectory != true else { continue }

                let standardizedURL = url.standardizedFileURL
                let item = FileItem(
                    id: standardizedURL,
                    url: standardizedURL,
                    name: url.lastPathComponent,
                    size: Int64(values.fileSize ?? 0),
                    modifiedDate: values.contentModificationDate,
                    contentType: values.contentType,
                    iCloudStatus: Self.status(from: values.ubiquitousItemDownloadingStatus)
                )
                batch.append(item)
                total += 1

                if batch.count >= batchSize {
                    let toSend = batch
                    batch = []
                    await MainActor.run { onBatch(toSend) }
                }
            }
            if !batch.isEmpty {
                let toSend = batch
                await MainActor.run { onBatch(toSend) }
            }
            // FIX 2: total in lokale Konstante kopieren vor dem letzten MainActor.run
            let finalTotal = total
            await MainActor.run { onComplete(finalTotal) }
        }
    }

    func cancel() {
        currentScanTask?.cancel()
    }

    private static func status(from raw: URLUbiquitousItemDownloadingStatus?) -> FileItem.ICloudStatus {
        guard let raw else { return .localOnly }
        // WICHTIG: .downloaded bedeutet "liegt lokal vor" (evtl. nicht die
        // allerneueste Version) — nur .notDownloaded bedeutet wirklich,
        // dass noch ein Download nötig ist. Vorher wurde .downloaded
        // fälschlich wie "muss noch geladen werden" behandelt.
        return raw == .notDownloaded ? .needsDownload : .downloaded
    }
}
