import SwiftUI

@Observable
@MainActor
final class RecentlyDeletedViewModel {
    var assets: [AssetSummary] = []
    var isLoading = true
    private(set) var hasLoadedAssets = false
    var selectedIds: Set<String> = []
    var isSelectionMode = false
    var isAccessible = false
    var errorMessage: String?
    var isDeleting = false

    private let photoService = PhotoLibraryService()

    var totalSize: Int64 {
        assets.reduce(0) { $0 + $1.fileSize }
    }

    var selectedSize: Int64 {
        assets.filter { selectedIds.contains($0.id) }
            .reduce(0) { $0 + $1.fileSize }
    }

    func loadIfNeeded() async {
        guard !hasLoadedAssets else { return }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        assets = await photoService.fetchRecentlyDeleted()
        isAccessible = !assets.isEmpty
        selectedIds.removeAll()
        isSelectionMode = false
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
        selectedIds = Set(assets.map(\.id))
    }

    func deselectAll() {
        selectedIds.removeAll()
    }

    func deleteSelected() async {
        guard !selectedIds.isEmpty, !isDeleting else { return }
        isDeleting = true
        do {
            try await photoService.deleteAssets(identifiers: Array(selectedIds))
            assets.removeAll { selectedIds.contains($0.id) }
            selectedIds.removeAll()
            isSelectionMode = false
        } catch {
            errorMessage = error.localizedDescription
        }
        isDeleting = false
    }

    func deleteAll() async {
        selectAll()
        await deleteSelected()
    }
}
