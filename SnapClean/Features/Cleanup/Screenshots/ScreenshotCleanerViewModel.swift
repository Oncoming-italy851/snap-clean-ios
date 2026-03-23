import SwiftUI

enum ScreenshotSortOrder: String, CaseIterable {
    case newest = "Newest"
    case oldest = "Oldest"
    case largest = "Largest"
}

@Observable
@MainActor
final class ScreenshotCleanerViewModel {
    var screenshots: [AssetSummary] = []
    var isLoading = true
    private(set) var hasLoadedScreenshots = false
    var selectedIds: Set<String> = []
    var isSelectionMode = false
    var sortOrder: ScreenshotSortOrder = .newest
    var errorMessage: String?
    var isDeleting = false

    private let photoService = PhotoLibraryService()

    var totalSize: Int64 {
        screenshots.reduce(0) { $0 + $1.fileSize }
    }

    var selectedSize: Int64 {
        screenshots.filter { selectedIds.contains($0.id) }
            .reduce(0) { $0 + $1.fileSize }
    }

    var sortedScreenshots: [AssetSummary] {
        switch sortOrder {
        case .newest:
            return screenshots.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        case .oldest:
            return screenshots.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        case .largest:
            return screenshots.sorted { $0.fileSize > $1.fileSize }
        }
    }

    func loadIfNeeded() async {
        guard !hasLoadedScreenshots else { return }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        screenshots = await photoService.fetchScreenshots()
        hasLoadedScreenshots = true
        isLoading = false
    }

    func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    func selectAll() {
        selectedIds = Set(sortedScreenshots.map(\.id))
    }

    func deselectAll() {
        selectedIds.removeAll()
    }

    func deleteSelected() async {
        guard !selectedIds.isEmpty, !isDeleting else { return }
        isDeleting = true
        do {
            try await photoService.deleteAssets(identifiers: Array(selectedIds))
            screenshots.removeAll { selectedIds.contains($0.id) }
            selectedIds.removeAll()
            isSelectionMode = false
        } catch {
            errorMessage = error.localizedDescription
        }
        isDeleting = false
    }

    func delete(assetId: String) async {
        do {
            try await photoService.deleteAssets(identifiers: [assetId])
            screenshots.removeAll { $0.id == assetId }
            selectedIds.remove(assetId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
