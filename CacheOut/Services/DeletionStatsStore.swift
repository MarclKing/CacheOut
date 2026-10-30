import Foundation

@Observable
class DeletionStatsStore {
    private(set) var totalDeletedCount: Int = 0
    private(set) var totalDeletedBytes: Int64 = 0
    private(set) var totalDeletedPhotos: Int = 0
    private(set) var totalDeletedVideos: Int = 0

    // NEU: nach den bestehenden private(set) var-Deklarationen
    private var weeklyBucket: [String: Int] = [:]   // "2026-W28" -> Bytes (als Int gespeichert)
    private let weeklyBucketKey = "weeklyFreedBytesBuckets"

    private let countKey = "totalDeletedCount"
    private let bytesKey = "totalDeletedBytes"
    private let photosKey = "totalDeletedPhotos"
    private let videosKey = "totalDeletedVideos"

    init() {
        totalDeletedCount = UserDefaults.standard.integer(forKey: countKey)
        totalDeletedBytes = Int64(UserDefaults.standard.integer(forKey: bytesKey))
        totalDeletedPhotos = UserDefaults.standard.integer(forKey: photosKey)
        totalDeletedVideos = UserDefaults.standard.integer(forKey: videosKey)
        // NEU: im init(), nach den bestehenden Zuweisungen
        weeklyBucket = (UserDefaults.standard.dictionary(forKey: weeklyBucketKey) as? [String: Int]) ?? [:]
    }

    // Bestehender Aufruf bleibt kompatibel
    func recordDeletion(count: Int, bytes: Int64) {
        totalDeletedCount += count
        totalDeletedBytes += bytes
        recordWeeklyBytes(bytes)
        persist()
    }

    // NEU — bitte in DeleteConfirmSheet verwenden, sobald du sie mir schickst
    func recordDeletion(photosCount: Int, videosCount: Int, bytes: Int64) {
        totalDeletedCount += photosCount + videosCount
        totalDeletedPhotos += photosCount
        totalDeletedVideos += videosCount
        totalDeletedBytes += bytes
        recordWeeklyBytes(bytes)
        persist()
    }

    // Komprimierung: nur Platz und Wochenwert, kein Loeschzaehler
    func recordSavings(bytes: Int64) {
        guard bytes > 0 else { return }
        totalDeletedBytes += bytes
        recordWeeklyBytes(bytes)
        persist()
    }

    // NEU: Reset aller Statistiken
    func resetAll() {
        totalDeletedCount = 0
        totalDeletedBytes = 0
        totalDeletedPhotos = 0
        totalDeletedVideos = 0
        weeklyBucket.removeAll()
        persist()
    }

    private func recordWeeklyBytes(_ bytes: Int64) {
        let key = weekKey(for: Date())
        weeklyBucket[key, default: 0] += Int(bytes)
        pruneWeeklyBucket()
    }

    private func pruneWeeklyBucket() {
        // Nur die letzten 12 Wochen behalten (Puffer über die im UI genutzten
        // letzten 6 hinaus) — verhindert unbegrenztes Wachstum über Jahre.
        // Bewusst über generierte Keys statt String-Vergleich, da "2026-W28"
        // nicht zero-gepaddet ist und lexikographisch nicht sauber sortiert
        // (z.B. "W9" > "W10" als String).
        let calendar = Calendar.current
        let keepKeys: Set<String> = Set((0..<12).compactMap { offset in
            calendar.date(byAdding: .weekOfYear, value: -offset, to: Date()).map { weekKey(for: $0) }
        })
        weeklyBucket = weeklyBucket.filter { keepKeys.contains($0.key) }
    }

    private func weekKey(for date: Date) -> String {
        let calendar = Calendar.current
        let week = calendar.component(.weekOfYear, from: date)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        return "\(year)-W\(week)"
    }

    // Letzte 6 Wochen, älteste zuerst — direkt für StorageTrendBanner nutzbar
    var weeklyFreedBytes: [Int64] {
        (0..<6).reversed().compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .weekOfYear, value: -offset, to: Date()) else { return nil }
            return Int64(weeklyBucket[weekKey(for: date)] ?? 0)
        }
    }

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalDeletedBytes, countStyle: .file)
    }

    private var persistTask: Task<Void, Never>?

    private func persist() {
        persistTask?.cancel()
        let count = totalDeletedCount, bytes = totalDeletedBytes
        let photos = totalDeletedPhotos, videos = totalDeletedVideos
        let weekly = weeklyBucket
        persistTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            UserDefaults.standard.set(count, forKey: countKey)
            UserDefaults.standard.set(Int(bytes), forKey: bytesKey)
            UserDefaults.standard.set(photos, forKey: photosKey)
            UserDefaults.standard.set(videos, forKey: videosKey)
            UserDefaults.standard.set(weekly, forKey: weeklyBucketKey)
        }
    }
}
