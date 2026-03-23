import SwiftUI

enum LargeFileFilter: String, CaseIterable {
    case all = "All"
    case photos = "Photos"
    case videos = "Videos"
}

enum LargeFileSortOrder: String, CaseIterable {
    case largest = "Largest"
    case newest = "Newest"
    case oldest = "Oldest"
    case filename = "Filename"
}

@Observable
@MainActor
final class LargeFilesViewModel {
    var assets: [AssetSummary] = []
    var isLoading = true
    private(set) var hasLoadedAssets = false
    var selectedIds: Set<String> = []
    var isSelectionMode = false
    var mediaFilter: LargeFileFilter = .all
    var sortOrder: LargeFileSortOrder = .largest
    var errorMessage: String?
    var isDeleting = false

    var thresholdMB: Double {
        get { AppPreferences.largeFileThresholdMB() }
        set { AppPreferences.saveLargeFileThresholdMB(newValue) }
    }

    private let photoService = PhotoLibraryService()

    var thresholdBytes: Int64 {
        Int64(thresholdMB * 1_000_000)
    }

    var filteredAssets: [AssetSummary] {
        var result = assets.filter { $0.fileSize >= thresholdBytes }
        switch mediaFilter {
        case .all: break
        case .photos: result = result.filter { $0.mediaType == .photo }
        case .videos: result = result.filter { $0.mediaType == .video }
        }
        switch sortOrder {
        case .largest:
            return result.sorted { $0.fileSize > $1.fileSize }
        case .newest:
            return result.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        case .oldest:
            return result.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        case .filename:
            return result.sorted {
                ($0.filename ?? "").localizedCaseInsensitiveCompare($1.filename ?? "") == .orderedAscending
            }
        }
    }

    var totalSize: Int64 {
        filteredAssets.reduce(0) { $0 + $1.fileSize }
    }

    var selectedSize: Int64 {
        filteredAssets.filter { selectedIds.contains($0.id) }
            .reduce(0) { $0 + $1.fileSize }
    }

    var selectedVisibleCount: Int {
        filteredAssets.filter { selectedIds.contains($0.id) }.count
    }

    var areAllVisibleSelected: Bool {
        !filteredAssets.isEmpty && selectedVisibleCount == filteredAssets.count
    }

    func loadIfNeeded() async {
        guard !hasLoadedAssets else { return }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        let allAssets = await photoService.fetchAssets(filter: .allMedia)
        assets = allAssets.sorted { $0.fileSize > $1.fileSize }
        synchronizeSelection()
        hasLoadedAssets = true
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
        selectedIds = Set(filteredAssets.map(\.id))
    }

    func deselectAll() {
        selectedIds.removeAll()
    }

    func synchronizeSelection() {
        selectedIds.formIntersection(Set(filteredAssets.map(\.id)))
    }

    func deleteSelected() async {
        guard !selectedIds.isEmpty, !isDeleting else { return }
        isDeleting = true
        do {
            let visibleSelectedIds = Set(filteredAssets.map(\.id)).intersection(selectedIds)
            try await photoService.deleteAssets(identifiers: Array(visibleSelectedIds))
            assets.removeAll { visibleSelectedIds.contains($0.id) }
            selectedIds.removeAll()
            isSelectionMode = false
        } catch {
            errorMessage = error.localizedDescription
        }
        isDeleting = false
    }
}
