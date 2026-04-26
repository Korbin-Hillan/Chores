import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @Environment(AuthStore.self) private var authStore
    @AppStorage("reminderEnabled") private var reminderEnabled = false
    @AppStorage("reminderHour") private var reminderHour = 9
    @AppStorage("reminderMinute") private var reminderMinute = 0

    @State private var permissionGranted = false
    @State private var chores: [APIChore] = []

    private var reminderTime: Date {
        get {
            Calendar.current.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: .now) ?? .now
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Daily reminder", isOn: $reminderEnabled)
                    .onChange(of: reminderEnabled) { _, enabled in
                        Task { await handleToggle(enabled: enabled) }
                    }
                if reminderEnabled {
                    DatePicker(
                        "Reminder time",
                        selection: Binding(
                            get: { reminderTime },
                            set: { date in
                                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                                reminderHour = comps.hour ?? 9
                                reminderMinute = comps.minute ?? 0
                                Task { await reschedule() }
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                }
            } footer: {
                Text("You'll get a reminder about recurring chores due today.")
            }

            if !permissionGranted && reminderEnabled {
                Section {
                    Button("Grant notification permission") {
                        Task {
                            permissionGranted = await NotificationScheduler.requestPermission()
                            if permissionGranted { await reschedule() }
                        }
                    }
                }
            }
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: authStore.currentHouseholdId) {
            chores = []
            await checkPermission()
            if reminderEnabled && permissionGranted {
                await reschedule()
            }
        }
    }

    private func checkPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permissionGranted = settings.authorizationStatus == .authorized
    }

    private func handleToggle(enabled: Bool) async {
        if enabled {
            if !permissionGranted {
                permissionGranted = await NotificationScheduler.requestPermission()
            }
            if permissionGranted { await reschedule() }
        } else {
            NotificationScheduler.cancelAllReminders()
        }
    }

    private func reschedule() async {
        if chores.isEmpty, let householdId = authStore.currentHouseholdId {
            let fetchedChores: [APIChore] = (try? await APIClient.shared.send(
                path: "/households/\(householdId)/chores"
            )) ?? []
            chores = fetchedChores
        }
        await NotificationScheduler.scheduleChoreReminder(
            hour: reminderHour,
            minute: reminderMinute,
            chores: chores
        )
    }
}
