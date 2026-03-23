import SwiftUI

struct CleanupToolInfo: Identifiable {
    let tool: CleanupTool
    var count: Int?
    var isLoading: Bool = true

    var id: CleanupTool { tool }
    var name: String { tool.name }
    var description: String { tool.description }
    var icon: String { tool.icon }
    var color: Color { tool.color }
}

@Observable
@MainActor
final class CleanupHomeViewModel {
    var tools: [CleanupToolInfo] = CleanupTool.allCases.map { CleanupToolInfo(tool: $0) }
    private(set) var hasLoadedCounts = false

    private let photoService = PhotoLibraryService()

    func loadCountsIfNeeded() async {
        guard !hasLoadedCounts else { return }
        hasLoadedCounts = true
        await loadCounts()
    }

    func refreshCounts() async {
        await loadCounts()
    }

    private func loadCounts() async {
        // Load counts for each tool asynchronously
        async let screenshotCount = photoService.fetchScreenshots().count
        async let livePhotoCount = photoService.fetchLivePhotos().count
        async let burstCount = photoService.fetchBurstPhotos().values.reduce(0) { $0 + $1.count }
        async let videoCount = photoService.fetchAssetsByMediaType(.video).count

        let screenshots = await screenshotCount
        let livePhotos = await livePhotoCount
        let bursts = await burstCount
        let videos = await videoCount

        updateTool(.screenshots, count: screenshots)
        updateTool(.livePhotos, count: livePhotos)
        updateTool(.bursts, count: bursts)
        updateTool(.videoCompression, count: videos)

        // Large files
        let allAssets = await photoService.fetchAssets(filter: .allMedia)
        let threshold = Int64(AppPreferences.largeFileThresholdMB() * 1_000_000)
        let largeCount = allAssets.filter { $0.fileSize >= threshold }.count
        updateTool(.largeFiles, count: largeCount)

        // Duplicates/similar - too expensive to scan, show nil (will display "Scan")
        updateTool(.duplicates, count: nil, isLoading: false)
        updateTool(.similar, count: nil, isLoading: false)
        updateTool(.blurry, count: nil, isLoading: false)

        // Recently Deleted is guidance-only because public PhotoKit access is unreliable.
        updateTool(.recentlyDeleted, count: nil, isLoading: false)
    }

    private func updateTool(_ tool: CleanupTool, count: Int?, isLoading: Bool = false) {
        if let index = tools.firstIndex(where: { $0.tool == tool }) {
            tools[index].count = count
            tools[index].isLoading = isLoading
        }
    }
}
