import SwiftUI

struct SimilarGroup: Identifiable, Hashable, Sendable {
    let id: String
    let assets: [AssetSummary]
    var bestAssetId: String
}

@Observable
@MainActor
final class SimilarPhotosViewModel {
    var groups: [SimilarGroup] = []
    var scanState: ScanState = .idle
    var selectedForDeletion: Set<String> = []
    var errorMessage: String?
    var isDeleting = false

    var timeWindow: Double {
        get { AppPreferences.similarPhotoTimeWindow() }
        set { AppPreferences.saveSimilarPhotoTimeWindow(newValue) }
    }

    private let photoService = PhotoLibraryService()

    var totalDuplicateCount: Int {
        groups.reduce(0) { $0 + $1.assets.count - 1 }
    }

    var totalSavingsBytes: Int64 {
        groups.reduce(Int64(0)) { total, group in
            let nonBest = group.assets.filter { $0.id != group.bestAssetId }
            return total + nonBest.reduce(Int64(0)) { $0 + $1.fileSize }
        }
    }

    var selectedSavingsBytes: Int64 {
        groups.reduce(Int64(0)) { total, group in
            total + group.assets.filter { selectedForDeletion.contains($0.id) }
                .reduce(0) { subtotal, asset in subtotal + asset.fileSize }
        }
    }

    func scan() async {
        scanState = .scanning(0)
        selectedForDeletion.removeAll()
        errorMessage = nil

        // Capture timeWindow at scan start to avoid inconsistent grouping
        // if the user changes the slider during the scan
        let capturedTimeWindow = timeWindow

        let photos = await photoService.fetchAllPhotos()
            .sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }

        var foundGroups: [SimilarGroup] = []
        var currentGroup: [AssetSummary] = []

        for (index, photo) in photos.enumerated() {
            if Task.isCancelled {
                scanState = .idle
                return
            }
            if currentGroup.isEmpty {
                currentGroup.append(photo)
            } else {
                let lastDate = currentGroup.last?.creationDate ?? .distantPast
                let currentDate = photo.creationDate ?? .distantPast
                let interval = currentDate.timeIntervalSince(lastDate)

                if interval <= capturedTimeWindow {
                    currentGroup.append(photo)
                } else {
                    if currentGroup.count >= 2 {
                        let best = selectBest(from: currentGroup)
                        foundGroups.append(SimilarGroup(
                            id: UUID().uuidString,
                            assets: currentGroup,
                            bestAssetId: best.id
                        ))
                    }
                    currentGroup = [photo]
                }
            }

            if index % 100 == 0 {
                scanState = .scanning(Float(index + 1) / Float(max(photos.count, 1)))
            }
        }

        scanState = .scanning(1.0)

        // Handle last group
        if currentGroup.count >= 2 {
            let best = selectBest(from: currentGroup)
            foundGroups.append(SimilarGroup(
                id: UUID().uuidString,
                assets: currentGroup,
                bestAssetId: best.id
            ))
        }

        groups = foundGroups
        scanState = .completed

        selectNonBestAssets()
    }

    func deleteSelected() async {
        guard !selectedForDeletion.isEmpty, !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await photoService.deleteAssets(identifiers: Array(selectedForDeletion))
            let deleted = selectedForDeletion
            groups = groups.compactMap { group in
                let remaining = group.assets.filter { !deleted.contains($0.id) }
                guard remaining.count > 1 else { return nil }
                let bestAssetId = remaining.contains(where: { $0.id == group.bestAssetId })
                    ? group.bestAssetId
                    : selectBest(from: remaining).id
                return SimilarGroup(id: group.id, assets: remaining, bestAssetId: bestAssetId)
            }
            selectNonBestAssets()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleSelection(_ assetId: String) {
        if selectedForDeletion.contains(assetId) {
            selectedForDeletion.remove(assetId)
        } else {
            selectedForDeletion.insert(assetId)
        }
    }

    func setBest(assetId: String, in groupId: String) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        let oldBest = groups[index].bestAssetId
        groups[index].bestAssetId = assetId
        selectedForDeletion.remove(assetId)
        if oldBest != assetId {
            selectedForDeletion.insert(oldBest)
        }
    }

    private func selectNonBestAssets() {
        selectedForDeletion = Set(
            groups.flatMap { group in
                group.assets.compactMap { asset in
                    asset.id == group.bestAssetId ? nil : asset.id
                }
            }
        )
    }

    private func selectBest(from assets: [AssetSummary]) -> AssetSummary {
        assets.max { a, b in
            let aResolution = a.pixelWidth * a.pixelHeight
            let bResolution = b.pixelWidth * b.pixelHeight
            if aResolution != bResolution { return aResolution < bResolution }
            let aModified = a.modificationDate ?? .distantPast
            let bModified = b.modificationDate ?? .distantPast
            return aModified < bModified
        } ?? assets[0]
    }
}
