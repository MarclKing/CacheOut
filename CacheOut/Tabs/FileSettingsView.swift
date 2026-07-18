import SwiftUI

struct FileSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(FileSwipeViewModel.self) private var fileViewModel

    var body: some View {
        @Bindable var fileViewModel = fileViewModel

        ScrollView {
            VStack(spacing: 24) {
                SettingsSection(title: "Dateien") {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(AppTheme.keepGreen, in: RoundedRectangle(cornerRadius: 8))
                        Text("Sortierung nach")
                        Spacer()
                        Picker("", selection: $fileViewModel.sortOrder) {
                            ForEach(FileSortOrder.allCases) { order in
                                Text(order.label).tag(order)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    Divider().padding(.leading, 52)
                    SettingsToggleRow(icon: "icloud.and.arrow.down.fill", iconColor: AppTheme.accent,
                                      title: "iCloud-Dateien automatisch laden", isOn: $fileViewModel.autoDownloadICloudEnabled)
                }
            }
            .padding()
        }
        .navigationTitle("Dateien")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        .background(AppTheme.background(colorScheme).ignoresSafeArea())
    }
}
