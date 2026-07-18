import Foundation
import UniformTypeIdentifiers

enum FileFilter: String, CaseIterable, Identifiable {
    case all, pdf, image, video, zip, word, excel, powerpoint, text
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Alle Dateien"
        case .pdf: return "PDFs"
        case .image: return "Bilder"
        case .video: return "Videos"
        case .zip: return "ZIP"
        case .word: return "Word"
        case .excel: return "Excel"
        case .powerpoint: return "PowerPoint"
        case .text: return "Textdateien"
        }
    }

    // Prüft, ob ein UTType zu diesem Filter passt.
    func matches(_ type: UTType?) -> Bool {
        guard let type else { return self == .all }
        switch self {
        case .all: return true
        case .pdf: return type.conforms(to: .pdf)
        case .image: return type.conforms(to: .image)
        case .video: return type.conforms(to: .movie)
        case .zip: return type.conforms(to: .zip) || type.conforms(to: .archive)
        case .word: return type.identifier.contains("wordprocessingml") || type.identifier == "com.microsoft.word.doc"
        case .excel: return type.identifier.contains("spreadsheetml") || type.identifier == "com.microsoft.excel.xls"
        case .powerpoint: return type.identifier.contains("presentationml") || type.identifier == "com.microsoft.powerpoint.ppt"
        case .text: return type.conforms(to: .text)
        }
    }
}
