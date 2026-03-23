import SwiftUI
import SwiftData

struct StorageCategory: Identifiable, Sendable {
    let id: String
    let name: String
    let bytes: Int64
    let count: Int
    let color: Color
}

struct CleanupOpportunity: Identifiable {
    let id: String
    let title: String
    let detail: String
    let tool: CleanupTool
    let icon: String
    let color: Color
}

struct DeviceStorageInfo: Sendable {
    var totalCapacity: Int64 = 0
    var availableCapacity: Int64 = 0
    var usedCapacity: Int64 { totalCapacity - availableCapacity }
}

@Observable
@MainActor
final class StorageDashboardViewModel {
    var categories: [StorageCategory] = []
    var deviceStorage = DeviceStorageInfo()
    var snapshots: [StorageSnapshot] = []
    var opportunities: [CleanupOpportunity] = []
    var isLoading = true
    var iCloudOnlyCount: Int = 0
    var iCloudOnlySize: Int64 = 0
    var localCount: Int = 0

    private let photoService = PhotoLibraryService()

    var totalLibrarySize: Int64 {
        categories.reduce(0) { $0 + $1.bytes }
    }

    var totalItemCount: Int {
        categories.reduce(0) { $0 + $1.count }
    }

    func load(modelContext: ModelContext) async {
        isLoading = true

        // Fetch storage breakdown
        let breakdown = await photoService.calculateStorageBreakdown()

        categories = [
            StorageCategory(id: "photos", name: "Photos", bytes: breakdown.photoBytes, count: breakdown.photoCount, color: .blue),
            StorageCategory(id: "videos", name: "Videos", bytes: breakdown.videoBytes, count: breakdown.videoCount, color: .purple),
            StorageCategory(id: "screenshots", name: "Screenshots", bytes: breakdown.screenshotBytes, count: breakdown.screenshotCount, color: .yellow),
            StorageCategory(id: "livePhotos", name: "Live Photos", bytes: breakdown.livePhotoBytes, count: breakdown.livePhotoCount, color: .teal),
            StorageCategory(id: "other", name: "Other", bytes: breakdown.otherBytes, count: breakdown.otherCount, color: .gray),
        ].filter { $0.bytes > 0 }

        // Device storage
        fetchDeviceStorage()

        // iCloud status
        await fetchICloudStatus()

        // Storage snapshots
        fetchSnapshots(modelContext: modelContext)

        // Compute cleanup opportunities
        await computeOpportunities()

        isLoading = false
    }

    private func fetchDeviceStorage() {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            deviceStorage.totalCapacity = (attrs[.systemSize] as? Int64) ?? 0
            deviceStorage.availableCapacity = (attrs[.systemFreeSize] as? Int64) ?? 0
        } catch {
            // Non-critical
        }
    }

    private func fetchICloudStatus() async {
        let allAssets = await photoService.fetchAssets(filter: .allMedia)
        iCloudOnlyCount = allAssets.filter { !$0.isLocallyAvailable }.count
        iCloudOnlySize = allAssets.filter { !$0.isLocallyAvailable }.reduce(0) { $0 + $1.fileSize }
        localCount = allAssets.filter(\.isLocallyAvailable).count
    }

    private func fetchSnapshots(modelContext: ModelContext) {
        var descriptor = FetchDescriptor<StorageSnapshot>(
            sortBy: [SortDescriptor(\.capturedAt, order: .forward)]
        )
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        descriptor.predicate = #Predicate { $0.capturedAt >= thirtyDaysAgo }
        snapshots = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func computeOpportunities() async {
        var opps: [CleanupOpportunity] = []

        let screenshots = await photoService.fetchScreenshots()
        if !screenshots.isEmpty {
            let size = screenshots.reduce(Int64(0)) { $0 + $1.fileSize }
            opps.append(CleanupOpportunity(
                id: "screenshots",
                title: "\(screenshots.count) screenshots",
                detail: "Free up \(size.formattedFileSize)",
                tool: .screenshots,
                icon: "camera.viewfinder",
                color: .yellow
            ))
        }

        let livePhotos = await photoService.fetchLivePhotos()
        if !livePhotos.isEmpty {
            let size = livePhotos.reduce(Int64(0)) { $0 + $1.fileSize } / 2
            opps.append(CleanupOpportunity(
                id: "livePhotos",
                title: "\(livePhotos.count) Live Photos",
                detail: "Save ~\(size.formattedFileSize) by converting",
                tool: .livePhotos,
                icon: "livephoto",
                color: .green
            ))
        }

        let allMedia = await photoService.fetchAssets(filter: .allMedia)
        let largeVideos = allMedia.filter { $0.mediaType == .video && $0.fileSize > 100_000_000 }
        if !largeVideos.isEmpty {
            let size = largeVideos.reduce(Int64(0)) { $0 + $1.fileSize }
            opps.append(CleanupOpportunity(
                id: "largeVideos",
                title: "\(largeVideos.count) videos over 100 MB",
                detail: "\(size.formattedFileSize) total",
                tool: .videoCompression,
                icon: "video.badge.waveform",
                color: .indigo
            ))
        }

        opportunities = opps
    }
}
