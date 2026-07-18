import SwiftUI

struct NotificationSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(NotificationManager.self) private var notificationManager

    var body: some View {
        @Bindable var notificationManager = notificationManager

        ScrollView {
            VStack(spacing: 24) {
                SettingsSection(title: "Erinnerungen") {
                    SettingsToggleRow(icon: "bell.badge.fill", iconColor: AppTheme.accent,
                                      title: "Tägliche Erinnerung", isOn: $notificationManager.dailyReminderEnabled)

                    if notificationManager.dailyReminderEnabled {
                        Divider().padding(.leading, 52)
                        HStack(spacing: 12) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 8))
                            Text("Uhrzeit")
                            Spacer()
                            DatePicker("", selection: $notificationManager.dailyReminderTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }

                    Divider().padding(.leading, 52)
                    SettingsToggleRow(icon: "flame.fill", iconColor: .orange,
                                      title: "Streak-Erinnerung", isOn: $notificationManager.streakReminderEnabled)
                }
            }
            .padding()
        }
        .navigationTitle("Benachrichtigungen")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        .background(AppTheme.background(colorScheme).ignoresSafeArea())
    }
}
