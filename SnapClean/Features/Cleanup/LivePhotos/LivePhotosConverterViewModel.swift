import SwiftUI
import Photos

enum ConversionState {
    case idle
    case converting
    case completed
    case failed(String)
}

struct LivePhotoItem: Identifiable {
    let id: String
    let asset: AssetSummary
    var conversionState: ConversionState = .idle
    var savedBytes: Int64 = 0
}

@Observable
@MainActor
final class LivePhotosConverterViewModel {
    var items: [LivePhotoItem] = []
    var isLoading = true
    private(set) var hasLoadedItems = false
    var selectedIds: Set<String> = []
    var isSelectionMode = false
    var convertingAll = false
    var errorMessage: String?
    var totalSavedBytes: Int64 = 0
    var convertedCount: Int = 0

    private let photoService = PhotoLibraryService()

    var totalSize: Int64 {
        items.reduce(0) { $0 + $1.asset.fileSize }
    }

    var estimatedSavings: Int64 {
        // Live Photos are roughly 2x the size of stills
        items.reduce(0) { $0 + $1.asset.fileSize / 2 }
    }

    func loadIfNeeded() async {
        guard !hasLoadedItems else { return }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        let livePhotos = await photoService.fetchLivePhotos()
        items = livePhotos.map { LivePhotoItem(id: $0.id, asset: $0) }
        hasLoadedItems = true
        isLoading = false
    }

    func convertSingle(itemId: String) async {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return }
        items[index].conversionState = .converting

        do {
            let savedBytes = try await performConversion(assetId: itemId)
            totalSavedBytes += savedBytes
            convertedCount += 1
            items[index].savedBytes = savedBytes
            items[index].conversionState = .completed
        } catch {
            items[index].conversionState = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func convertAll() async {
        convertingAll = true
        let pendingIds = items.map(\.id)
        for itemId in pendingIds {
            guard let index = items.firstIndex(where: { $0.id == itemId }) else { continue }
            guard case .idle = items[index].conversionState else { continue }
            items[index].conversionState = .converting
            do {
                let savedBytes = try await performConversion(assetId: itemId)
                totalSavedBytes += savedBytes
                convertedCount += 1
                items[index].savedBytes = savedBytes
                items[index].conversionState = .completed
            } catch {
                items[index].conversionState = .failed(error.localizedDescription)
                errorMessage = error.localizedDescription
            }
        }
        convertingAll = false
    }

    private func performConversion(assetId: String) async throws -> Int64 {
        guard let phAsset = await photoService.getPHAsset(for: assetId) else {
            throw LivePhotoError.assetNotFound
        }

        let resources = PHAssetResource.assetResources(for: phAsset)
        guard let photoResource = resources.first(where: { $0.type == .photo }) else {
            throw LivePhotoError.noPhotoResource
        }

        let originalSize = resources.reduce(Int64(0)) { total, resource in
            guard resource.responds(to: Selector(("fileSize"))),
                  let size = resource.value(forKey: "fileSize") as? Int64 else {
                return total
            }
            return total + size
        }

        // Export the still image data
        let imageData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            var data = Data()
            PHAssetResourceManager.default().requestData(
                for: photoResource,
                options: nil
            ) { chunk in
                data.append(chunk)
            } completionHandler: { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }

        guard let image = UIImage(data: imageData) else {
            throw LivePhotoError.invalidImageData
        }

        // Save as new still photo and verify creation before deleting original
        var placeholder: PHObjectPlaceholder?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
            placeholder = request.placeholderForCreatedAsset
        }

        guard placeholder?.localIdentifier != nil else {
            throw LivePhotoError.invalidImageData
        }

        // Delete original Live Photo only after confirming new asset was created
        try await photoService.deleteAssets(identifiers: [assetId])

        let newSize = Int64(imageData.count)
        return originalSize - newSize
    }
}

enum LivePhotoError: LocalizedError {
    case assetNotFound
    case noPhotoResource
    case invalidImageData

    var errorDescription: String? {
        switch self {
        case .assetNotFound: "Live Photo not found."
        case .noPhotoResource: "Could not find still image in Live Photo."
        case .invalidImageData: "Invalid image data."
        }
    }
}
