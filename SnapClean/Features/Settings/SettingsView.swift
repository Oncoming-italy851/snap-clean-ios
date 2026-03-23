import SwiftUI
import SwiftData

struct SettingsView: View {
    // Swipe
    @AppStorage(AppPreferences.Key.defaultSwipeFilter) private var defaultSwipeFilter: String = DefaultSwipeFilterPreference.notSwipedYet.rawValue

    // Similar Photos
    @AppStorage(AppPreferences.Key.similarPhotoTimeWindow) private var timeWindow: Double = 5.0

    // Blur Detection
    @AppStorage(AppPreferences.Key.blurSensitivity) private var blurSensitivity: String = BlurSensitivity.medium.rawValue

    // Large Files
    @AppStorage(AppPreferences.Key.largeFileThresholdMB) private var largeFileThreshold: Double = 10.0

    // Video Compression
    @AppStorage(AppPreferences.Key.defaultCompressionPreset) private var compressionPreset: String = "1080p"

    // Notifications
    @AppStorage(AppPreferences.Key.cleanupRemindersEnabled) private var remindersEnabled: Bool = false
    @AppStorage(AppPreferences.Key.reminderWeekday) private var reminderWeekday: Int = 1 // Sunday

    @State private var showResetConfirm = false
    @Environment(\.modelContext) private var modelContext

    private let weekdays = [
        (1, "Sunday"), (2, "Monday"), (3, "Tuesday"), (4, "Wednesday"),
        (5, "Thursday"), (6, "Friday"), (7, "Saturday")
    ]

    var body: some View {
        Form {
            // MARK: - Swipe Settings
            Section("Swipe") {
                Picker("Default Filter", selection: $defaultSwipeFilter) {
                    ForEach(DefaultSwipeFilterPreference.allCases, id: \.self) { filter in
                        Text(filter.title).tag(filter.rawValue)
                    }
                }
            }

            // MARK: - Cleanup Settings
            Section("Cleanup") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Similar Photo Time Window")
                    HStack {
                        Slider(value: $timeWindow, in: 1...60, step: 1)
                        Text("\(Int(timeWindow))s")
                            .monospacedDigit()
                            .frame(width: 36)
                    }
                }

                Picker("Blur Detection Sensitivity", selection: $blurSensitivity) {
                    ForEach(BlurSensitivity.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(level.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Large File Threshold")
                    HStack {
                        Slider(value: $largeFileThreshold, in: 5...500, step: 5)
                        Text("\(Int(largeFileThreshold)) MB")
                            .monospacedDigit()
                            .frame(width: 60)
                    }
                }
            }

            // MARK: - Video Compression
            Section("Video Compression") {
                Picker("Default Preset", selection: $compressionPreset) {
                    ForEach(CompressionPreset.presets) { preset in
                        Text(preset.label).tag(preset.id)
                    }
                }
            }

            // MARK: - Notifications
            Section("Reminders") {
                Toggle("Cleanup Reminders", isOn: $remindersEnabled)
                    .onChange(of: remindersEnabled) { _, enabled in
                        if enabled {
                            Task {
                                let granted = await NotificationService.requestPermission()
                                if !granted {
                                    remindersEnabled = false
                                } else {
                                    await NotificationService.scheduleWeeklyReminder(weekday: reminderWeekday)
                                }
                            }
                        } else {
                            NotificationService.cancelAllReminders()
                        }
                    }

                if remindersEnabled {
                    Picker("Reminder Day", selection: $reminderWeekday) {
                        ForEach(weekdays, id: \.0) { day in
                            Text(day.1).tag(day.0)
                        }
                    }
                    .onChange(of: reminderWeekday) { _, newDay in
                        Task {
                            await NotificationService.scheduleWeeklyReminder(weekday: newDay)
                        }
                    }
                }
            }

            // MARK: - Data
            Section("Data") {
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Text("Reset Swipe History")
                }
            }

            // MARK: - About
            Section("About") {
                HStack {
                    Text("App")
                    Spacer()
                    Text("SnapClean")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Build")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .alert("Reset Swipe History", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetSwipeHistory()
            }
        } message: {
            Text("This will clear all swipe records. All photos will appear as \"Not Swiped Yet\" again. This cannot be undone.")
        }
    }

    private func resetSwipeHistory() {
        do {
            try modelContext.delete(model: SwipeRecord.self)
            try modelContext.save()
        } catch {
            // Non-critical
        }
    }
}
