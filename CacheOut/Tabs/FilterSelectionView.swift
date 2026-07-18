import SwiftUI

struct FilterSelectionView: View {
    @Bindable var viewModel: FileSwipeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Dateityp") {
                    Picker("Filter", selection: $viewModel.filter) {
                        ForEach(FileFilter.allCases) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                    .pickerStyle(.inline)
                }
                Section("Sortierung") {
                    Picker("Sortierung", selection: $viewModel.sortOrder) {
                        ForEach(FileSortOrder.allCases) { order in
                            Text(order.label).tag(order)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle("Filter und Sortierung")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Starten") { dismiss() }
                }
            }
        }
    }
}
