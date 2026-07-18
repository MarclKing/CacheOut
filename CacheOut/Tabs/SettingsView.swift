import SwiftUI

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppSettingsStore.self) private var appSettings

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    var body: some View {
        @Bindable var appSettings = appSettings

        ScrollView {
            VStack(spacing: 24) {
                SettingsSection(title: "Wiedergabe & Verhalten") {
                    SettingsToggleRow(icon: "hand.tap.fill", iconColor: AppTheme.accent,
                                      title: "Haptisches Feedback", isOn: $appSettings.hapticsEnabled)
                    Divider().padding(.leading, 52)
                    SettingsToggleRow(icon: "play.rectangle.fill", iconColor: AppTheme.keepGreen,
                                      title: "Videos automatisch abspielen", isOn: $appSettings.videoAutoplayEnabled)
                    Divider().padding(.leading, 52)
                    SettingsToggleRow(icon: "wifi.slash", iconColor: .orange,
                                      title: "Datensparmodus (Fotos)", isOn: $appSettings.dataSaverEnabled)
                    Divider().padding(.leading, 52)
                    SettingsToggleRow(icon: "rectangle.compress.vertical", iconColor: .purple,
                                      title: "Reduzierte Bewegung beim Swipen", isOn: $appSettings.reducedSwipeMotionEnabled)
                }

                SettingsSection(title: "") {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        SettingsNavRow(icon: "bell.badge.fill", iconColor: AppTheme.accent,
                                       title: "Benachrichtigungen", value: nil)
                    }
                    Divider().padding(.leading, 52)
                    NavigationLink {
                        FileSettingsView()
                    } label: {
                        SettingsNavRow(icon: "doc.fill", iconColor: AppTheme.keepGreen,
                                       title: "Dateien", value: nil)
                    }
                    Divider().padding(.leading, 52)
                    NavigationLink {
                        DataManagementSettingsView()
                    } label: {
                        SettingsNavRow(icon: "externaldrive.fill", iconColor: .secondary,
                                       title: "Datenverwaltung", value: nil)
                    }
                }

                SettingsSection(title: "Über die App") {
                    StatRow(icon: "info.circle.fill", iconColor: .secondary,
                            label: "Version", value: appVersionString)
                }
            }
            .padding()
        }
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        .background(AppTheme.background(colorScheme).ignoresSafeArea())
    }
}

// MARK: - Wiederverwendete Bausteine (jetzt internal statt private,
// damit die ausgelagerten Unterseiten sie ebenfalls nutzen können)

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title.uppercased())
                    .font(.caption).bold()
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) { content }
                .glassCard()
        }
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(iconColor, in: RoundedRectangle(cornerRadius: 8))
            Text(title)
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct SettingsNavRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var value: String?
    var showChevron: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(iconColor, in: RoundedRectangle(cornerRadius: 8))
            Text(title)
                .foregroundStyle(iconColor == AppTheme.deleteRed ? AppTheme.deleteRed : Color.primary)
            Spacer()
            if let value {
                Text(value).foregroundStyle(.secondary)
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct StatRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(iconColor, in: RoundedRectangle(cornerRadius: 8))
            Text(label)
            Spacer()
            Text(value).bold()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
