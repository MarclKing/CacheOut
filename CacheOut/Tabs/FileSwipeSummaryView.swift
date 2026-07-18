import SwiftUI

struct FileSwipeSummaryView: View {
    let viewModel: FileSwipeViewModel
    let onRestart: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(AppTheme.keepGreen)

            Text("Fertig aufgeräumt!")
                .font(.title2).bold()

            VStack(spacing: 8) {
                summaryRow(label: "Gelöscht", value: "\(viewModel.deletedCount)")
                summaryRow(label: "Behalten", value: "\(viewModel.keptCount)")
                summaryRow(label: "Speicher freigegeben", value: formattedFreed)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

            Button("Neuen Ordner auswählen") { onRestart() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var formattedFreed: String {
        ByteCountFormatter.string(fromByteCount: viewModel.freedBytes, countStyle: .file)
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold()
        }
    }
}
