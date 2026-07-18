import Foundation

enum FileSortOrder: String, CaseIterable, Identifiable {
    case largest, oldest, newest, alphabetical
    var id: String { rawValue }

    var label: String {
        switch self {
        case .largest: return "Größte"
        case .oldest: return "Älteste"
        case .newest: return "Neueste"
        case .alphabetical: return "Alphabetisch"
        }
    }

    func sort(_ items: [FileItem]) -> [FileItem] {
        switch self {
        case .largest: return items.sorted { $0.size > $1.size }
        case .oldest: return items.sorted { ($0.modifiedDate ?? .distantPast) < ($1.modifiedDate ?? .distantPast) }
        case .newest: return items.sorted { ($0.modifiedDate ?? .distantPast) > ($1.modifiedDate ?? .distantPast) }
        case .alphabetical: return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
}
