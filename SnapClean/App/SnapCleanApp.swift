import SwiftUI
import SwiftData
import Photos

@main
struct SnapCleanApp: App {
    let modelContainer: ModelContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let schema = Schema([
            SwipeRecord.self,
            CompressionRecord.self,
            StorageSnapshot.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    await handleSceneActivation()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task { await handleSceneActivation() }
                    }
                }
        }
        .modelContainer(modelContainer)
    }

    @MainActor
    private func handleSceneActivation() async {
        await recordStorageSnapshotIfNeeded()
        await refreshNotificationIfNeeded()
    }

    @MainActor
    private func refreshNotificationIfNeeded() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }
        let remindersEnabled = AppPreferences.remindersEnabled()
        guard remindersEnabled else { return }

        let weekday = AppPreferences.reminderWeekday()
        guard weekday > 0 else { return }

        // Compute current stats for dynamic notification body
        let photoService = PhotoLibraryService()
        let screenshots = await photoService.fetchScreenshots()
        let allAssets = await photoService.fetchAssets(filter: .allMedia)
        let threshold = Int64(AppPreferences.largeFileThresholdMB() * 1_000_000)
        let largeFiles = allAssets.filter { $0.fileSize >= threshold }
        let totalSize = allAssets.reduce(Int64(0)) { $0 + $1.fileSize }

        await NotificationService.scheduleWeeklyReminder(
            weekday: weekday,
            screenshotCount: screenshots.count,
            largeFileCount: largeFiles.count,
            librarySize: totalSize.formattedFileSize
        )
    }

    @MainActor
    private func recordStorageSnapshotIfNeeded() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }

        let modelContext = modelContainer.mainContext
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        let descriptor = FetchDescriptor<StorageSnapshot>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )

        if let latestSnapshot = (try? modelContext.fetch(descriptor))?.first,
           calendar.isDate(latestSnapshot.capturedAt, inSameDayAs: today) {
            return
        }

        let photoService = PhotoLibraryService()
        let breakdown = await photoService.calculateStorageBreakdown()
        let snapshot = StorageSnapshot(
            photoBytes: breakdown.photoBytes + breakdown.livePhotoBytes,
            videoBytes: breakdown.videoBytes,
            screenshotBytes: breakdown.screenshotBytes,
            otherBytes: breakdown.otherBytes
        )
        modelContext.insert(snapshot)
        try? modelContext.save()
    }
}
