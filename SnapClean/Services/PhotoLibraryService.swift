import Photos
import UIKit

struct StorageBreakdown: Sendable {
    var photoBytes: Int64 = 0
    var videoBytes: Int64 = 0
    var screenshotBytes: Int64 = 0
    var livePhotoBytes: Int64 = 0
    var otherBytes: Int64 = 0
    var photoCount: Int = 0
    var videoCount: Int = 0
    var screenshotCount: Int = 0
    var livePhotoCount: Int = 0
    var otherCount: Int = 0

    var totalBytes: Int64 {
        photoBytes + videoBytes + screenshotBytes + livePhotoBytes + otherBytes
    }

    var totalCount: Int {
        photoCount + videoCount + screenshotCount + livePhotoCount + otherCount
    }
}

enum SwipeFilter: Sendable, Hashable {
    case allMedia
    case notInAnyAlbum
    case specificAlbum(id: String)
    case notSwipedYet
    case screenshots
    case customAssetIds(Set<String>)
}

actor PhotoLibraryService {

    private let imageManager = PHCachingImageManager()
    private var changeObserverHelper: PhotoLibraryChangeObserverHelper?

    // Called when the photo library changes — consumers can listen via this callback
    private var onLibraryChange: (@Sendable () -> Void)?

    init() {
        imageManager.allowsCachingHighQualityImages = true
    }

    // MARK: - Authorization

    func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    func currentAuthorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    // MARK: - Change Observation

    func startObservingChanges(onChange: @escaping @Sendable () -> Void) {
        self.onLibraryChange = onChange
        let helper = PhotoLibraryChangeObserverHelper { [weak self] in
            Task { [weak self] in
                await self?.handleLibraryChange()
            }
        }
        self.changeObserverHelper = helper
        PHPhotoLibrary.shared().register(helper)
    }

    func stopObservingChanges() {
        if let helper = changeObserverHelper {
            PHPhotoLibrary.shared().unregisterChangeObserver(helper)
            changeObserverHelper = nil
        }
        onLibraryChange = nil
    }

    private func handleLibraryChange() {
        onLibraryChange?()
    }

    // MARK: - Album Fetching

    func fetchUserAlbums() -> [AlbumInfo] {
        var albums: [AlbumInfo] = []

        // Smart albums (Favorites, Recents, etc.)
        let smartAlbums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .any,
            options: nil
        )
        smartAlbums.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            guard count > 0 else { return }
            let thumbnailId = self.firstThumbnailId(in: collection)
            albums.append(AlbumInfo(
                id: collection.localIdentifier,
                title: collection.localizedTitle ?? "Untitled",
                count: count,
                type: .smartAlbum,
                thumbnailAssetId: thumbnailId
            ))
        }

        // User-created albums
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: nil
        )
        userAlbums.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            guard count > 0 else { return }
            let thumbnailId = self.firstThumbnailId(in: collection)
            albums.append(AlbumInfo(
                id: collection.localIdentifier,
                title: collection.localizedTitle ?? "Untitled",
                count: count,
                type: .userAlbum,
                thumbnailAssetId: thumbnailId
            ))
        }

        // Smart albums first, then user albums, both sorted alphabetically
        let smart = albums.filter { $0.type == .smartAlbum }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let user = albums.filter { $0.type == .userAlbum }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return smart + user
    }

    nonisolated private func firstThumbnailId(in collection: PHAssetCollection) -> String? {
        let options = PHFetchOptions()
        options.fetchLimit = 1
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(in: collection, options: options).firstObject?.localIdentifier
    }

    // MARK: - Asset Fetching

    func fetchAssets(filter: SwipeFilter, swipedIdentifiers: Set<String> = []) -> [AssetSummary] {
        switch filter {
        case .allMedia:
            let fetchResult = PHAsset.fetchAssets(with: allAssetsFetchOptions())
            return extractSummaries(from: fetchResult)

        case .notInAnyAlbum:
            let allAssets = PHAsset.fetchAssets(with: allAssetsFetchOptions())
            let assetsInAlbums = collectAssetsInUserAlbums()
            return extractSummaries(from: allAssets, excluding: assetsInAlbums)

        case .specificAlbum(let albumId):
            guard let collection = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [albumId], options: nil
            ).firstObject else {
                return []
            }
            let fetchResult = PHAsset.fetchAssets(in: collection, options: allAssetsFetchOptions())
            return extractSummaries(from: fetchResult)

        case .notSwipedYet:
            let allAssets = PHAsset.fetchAssets(with: allAssetsFetchOptions())
            return extractSummaries(from: allAssets, excluding: swipedIdentifiers)

        case .screenshots:
            let options = allAssetsFetchOptions()
            options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
            let fetchResult = PHAsset.fetchAssets(with: options)
            return extractSummaries(from: fetchResult)

        case .customAssetIds(let ids):
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil)
            return extractSummaries(from: assets)
        }
    }

    func fetchAssetsByMediaType(_ mediaType: PHAssetMediaType) -> [AssetSummary] {
        let options = allAssetsFetchOptions()
        options.predicate = NSPredicate(format: "mediaType = %d", mediaType.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        return extractSummaries(from: result)
    }

    func fetchScreenshots() -> [AssetSummary] {
        let options = allAssetsFetchOptions()
        options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        return extractSummaries(from: result)
    }

    func fetchLivePhotos() -> [AssetSummary] {
        let options = allAssetsFetchOptions()
        options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoLive.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        return extractSummaries(from: result)
    }

    func fetchBurstPhotos() -> [String: [AssetSummary]] {
        let allAssets = PHAsset.fetchAssets(with: allAssetsFetchOptions())

        var groups: [String: [AssetSummary]] = [:]
        allAssets.enumerateObjects { asset, _, _ in
            if asset.representsBurst, let burstId = asset.burstIdentifier {
                let summary = self.makeSummary(from: asset)
                groups[burstId, default: []].append(summary)
            }
        }
        return groups.filter { $0.value.count > 1 }
    }

    func fetchRecentlyDeleted() -> [AssetSummary] {
        // PhotoKit does not expose a stable public API for third-party access to
        // Recently Deleted. We intentionally fall back to guidance in the UI.
        []
    }

    func fetchAllPhotos() -> [AssetSummary] {
        let options = allAssetsFetchOptions()
        options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        return extractSummaries(from: result)
    }

    // MARK: - Image Loading

    func loadImage(for assetId: String, targetSize: CGSize, contentMode: PHImageContentMode = .aspectFill) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject else {
            return nil
        }
        return await loadImage(for: asset, targetSize: targetSize, contentMode: contentMode)
    }

    func loadImage(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode = .aspectFill) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            nonisolated(unsafe) var hasResumed = false
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded && !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: image)
                }
            }
        }
    }

    func loadThumbnail(for assetId: String, size: CGSize = CGSize(width: 200, height: 200)) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            nonisolated(unsafe) var hasResumed = false
            imageManager.requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded && !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: image)
                }
            }
        }
    }

    // MARK: - Album Membership

    func albumsContaining(assetId: String) -> [String] {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject else {
            return []
        }
        var albumNames: [String] = []
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            let opts = PHFetchOptions()
            opts.predicate = NSPredicate(format: "localIdentifier = %@", assetId)
            let count = PHAsset.fetchAssets(in: collection, options: opts).count
            if count > 0 {
                albumNames.append(collection.localizedTitle ?? "Untitled")
            }
        }
        return albumNames
    }

    // MARK: - Pre-fetching

    func startCaching(assetIds: [String], targetSize: CGSize) {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIds, options: nil)
        var phAssets: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            phAssets.append(asset)
        }
        imageManager.startCachingImages(for: phAssets, targetSize: targetSize, contentMode: .aspectFill, options: nil)
    }

    func stopCaching(assetIds: [String], targetSize: CGSize) {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIds, options: nil)
        var phAssets: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            phAssets.append(asset)
        }
        imageManager.stopCachingImages(for: phAssets, targetSize: targetSize, contentMode: .aspectFill, options: nil)
    }

    func stopAllCaching() {
        imageManager.stopCachingImagesForAllAssets()
    }

    // MARK: - Mutations

    func deleteAssets(identifiers: [String]) async throws {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets)
        }
    }

    func addToAlbum(assetIdentifiers: [String], albumIdentifier: String) async throws {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIdentifiers, options: nil)
        guard let album = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumIdentifier], options: nil
        ).firstObject else {
            throw PhotoServiceError.albumNotFound
        }

        try await PHPhotoLibrary.shared().performChanges {
            guard let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) else { return }
            albumChangeRequest.addAssets(assets)
        }
    }

    func removeFromAlbum(assetIdentifiers: [String], albumIdentifier: String) async throws {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIdentifiers, options: nil)
        guard let album = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumIdentifier], options: nil
        ).firstObject else {
            throw PhotoServiceError.albumNotFound
        }

        try await PHPhotoLibrary.shared().performChanges {
            guard let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) else { return }
            albumChangeRequest.removeAssets(assets)
        }
    }

    func createAlbum(name: String) async throws -> String {
        var placeholder: PHObjectPlaceholder?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            placeholder = request.placeholderForCreatedAssetCollection
        }
        guard let id = placeholder?.localIdentifier else {
            throw PhotoServiceError.albumCreationFailed
        }
        return id
    }

    // MARK: - Storage Calculation

    func calculateStorageBreakdown() -> StorageBreakdown {
        var breakdown = StorageBreakdown()

        let allAssets = PHAsset.fetchAssets(with: allAssetsFetchOptions())
        allAssets.enumerateObjects { asset, _, _ in
            let size = self.estimateFileSize(for: asset)
            let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
            let isLivePhoto = asset.mediaSubtypes.contains(.photoLive)

            switch asset.mediaType {
            case .image:
                if isScreenshot {
                    breakdown.screenshotBytes += size
                    breakdown.screenshotCount += 1
                } else if isLivePhoto {
                    breakdown.livePhotoBytes += size
                    breakdown.livePhotoCount += 1
                } else {
                    breakdown.photoBytes += size
                    breakdown.photoCount += 1
                }
            case .video:
                breakdown.videoBytes += size
                breakdown.videoCount += 1
            default:
                breakdown.otherBytes += size
                breakdown.otherCount += 1
            }
        }

        return breakdown
    }

    // MARK: - Asset Data

    func loadFullImageData(for assetId: String) async -> Data? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            nonisolated(unsafe) var hasResumed = false
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, _, _, _ in
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: data)
            }
        }
    }

    func loadPrimaryResourceData(for assetId: String) async -> Data? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject else {
            return nil
        }

        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = preferredPrimaryResource(from: resources) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            var data = Data()
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true

            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options
            ) { chunk in
                data.append(chunk)
            } completionHandler: { error in
                if error != nil {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }

    nonisolated func getPHAsset(for identifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
    }

    // MARK: - Helpers

    nonisolated private func allAssetsFetchOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.includeAllBurstAssets = true
        return options
    }

    nonisolated private func estimateFileSize(for asset: PHAsset) -> Int64 {
        let resources = PHAssetResource.assetResources(for: asset)
        var totalSize: Int64 = 0
        for resource in resources {
            totalSize += safeFileSize(for: resource)
        }
        return totalSize
    }

    nonisolated private func makeSummary(from asset: PHAsset) -> AssetSummary {
        let resources = PHAssetResource.assetResources(for: asset)
        let isLocal = resources.allSatisfy { resource in
            guard resource.responds(to: Selector(("locallyAvailable"))) else { return true }
            return (resource.value(forKey: "locallyAvailable") as? Bool) ?? true
        }

        let mediaType: MediaType
        switch asset.mediaType {
        case .image:
            mediaType = .photo
        case .video:
            mediaType = .video
        case .audio:
            mediaType = .audio
        default:
            mediaType = .unknown
        }

        return AssetSummary(
            id: asset.localIdentifier,
            mediaType: mediaType,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            duration: asset.duration,
            fileSize: estimateFileSize(for: asset),
            filename: resources.first?.originalFilename,
            isFavorite: asset.isFavorite,
            isBurst: asset.representsBurst,
            burstIdentifier: asset.burstIdentifier,
            isLivePhoto: asset.mediaSubtypes.contains(.photoLive),
            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
            isLocallyAvailable: isLocal
        )
    }

    nonisolated private func extractSummaries(from fetchResult: PHFetchResult<PHAsset>, excluding: Set<String> = [], sort: Bool = true) -> [AssetSummary] {
        var summaries: [AssetSummary] = []
        summaries.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            if !excluding.contains(asset.localIdentifier) {
                summaries.append(self.makeSummary(from: asset))
            }
        }
        if sort {
            summaries.sort { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        }
        return summaries
    }

    nonisolated private func collectAssetsInUserAlbums() -> Set<String> {
        var inAlbum = Set<String>()
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            assets.enumerateObjects { asset, _, _ in
                inAlbum.insert(asset.localIdentifier)
            }
        }
        return inAlbum
    }

    nonisolated private func preferredPrimaryResource(from resources: [PHAssetResource]) -> PHAssetResource? {
        resources.first { $0.type == .fullSizePhoto }
        ?? resources.first { $0.type == .photo }
        ?? resources.first { $0.type == .fullSizeVideo }
        ?? resources.first { $0.type == .video }
        ?? resources.first { $0.type == .audio }
        ?? resources.first
    }

    nonisolated private func safeFileSize(for resource: PHAssetResource) -> Int64 {
        guard resource.responds(to: Selector(("fileSize"))),
              let size = resource.value(forKey: "fileSize") as? Int64 else {
            return 0
        }
        return size
    }
}

// MARK: - Errors

enum PhotoServiceError: LocalizedError {
    case albumNotFound
    case albumCreationFailed
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .albumNotFound: "Album not found."
        case .albumCreationFailed: "Failed to create album."
        case .unauthorized: "Photo library access not authorized."
        }
    }
}

// MARK: - Change Observer Helper

final class PhotoLibraryChangeObserverHelper: NSObject, PHPhotoLibraryChangeObserver, Sendable {
    private let onChange: @Sendable () -> Void

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        super.init()
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange()
    }
}
