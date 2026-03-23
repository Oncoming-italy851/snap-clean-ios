import CryptoKit
import Photos
import UIKit
import Vision

struct DuplicateGroup: Identifiable, Sendable {
    let id: String
    let assets: [AssetSummary]
    let bestAssetId: String
    let type: DuplicateType
}

enum DuplicateType: String, Sendable {
    case exact
    case visual
}

actor DuplicateDetectionService {
    private let photoService: PhotoLibraryService
    private let visionService: VisionAnalysisService

    init(photoService: PhotoLibraryService, visionService: VisionAnalysisService) {
        self.photoService = photoService
        self.visionService = visionService
    }

    // MARK: - Exact Duplicate Detection

    func findExactDuplicates(
        assets: [AssetSummary],
        progress: @Sendable (Float) -> Void
    ) async -> [DuplicateGroup] {
        // Pre-filter: group by (width, height, mediaType) to reduce comparisons
        var candidates: [String: [AssetSummary]] = [:]
        for asset in assets {
            let key = "\(asset.pixelWidth)x\(asset.pixelHeight)_\(asset.mediaType)"
            candidates[key, default: []].append(asset)
        }

        // Only keep groups with potential duplicates
        let potentialGroups = candidates.values.filter { $0.count > 1 }
        let totalAssets = potentialGroups.reduce(0) { $0 + $1.count }
        var processed = 0

        var hashGroups: [String: [AssetSummary]] = [:]

        for group in potentialGroups {
            for asset in group {
                if Task.isCancelled { return [] }
                if processed % 20 == 0 {
                    await Task.yield()
                }
                if let data = await photoService.loadPrimaryResourceData(for: asset.id) {
                    let hash = SHA256.hash(data: data)
                    let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
                    hashGroups[hashString, default: []].append(asset)
                }
                processed += 1
                progress(Float(processed) / Float(max(totalAssets, 1)))
            }
        }

        return hashGroups
            .filter { $0.value.count > 1 }
            .map { (hash, assets) in
                let best = selectBestAsset(from: assets)
                return DuplicateGroup(
                    id: hash,
                    assets: assets,
                    bestAssetId: best.id,
                    type: .exact
                )
            }
            .sorted { $0.assets.count > $1.assets.count }
    }

    // MARK: - Visual Duplicate Detection

    func findVisualDuplicates(
        assets: [AssetSummary],
        threshold: Float = 0.5,
        progress: @Sendable (Float) -> Void
    ) async -> [DuplicateGroup] {
        let photoAssets = assets.filter { $0.mediaType == .photo }

        // Generate feature prints
        var featurePrints: [(AssetSummary, VNFeaturePrintObservation)] = []
        let total = photoAssets.count

        for (index, asset) in photoAssets.enumerated() {
            if Task.isCancelled { return [] }
            if index % 20 == 0 {
                await Task.yield()
            }
            if let image = await loadCGImage(for: asset.id) {
                if let fp = await visionService.generateFeaturePrint(image: image) {
                    featurePrints.append((asset, fp))
                }
            }
            progress(Float(index + 1) / Float(max(total, 1)) * 0.7) // 70% for generation
        }

        // Compare and group
        var visited = Set<String>()
        var groups: [DuplicateGroup] = []
        let comparisons = featurePrints.count

        for i in 0..<featurePrints.count {
            if Task.isCancelled { return [] }
            guard !visited.contains(featurePrints[i].0.id) else { continue }

            var group: [AssetSummary] = [featurePrints[i].0]
            visited.insert(featurePrints[i].0.id)

            for j in (i + 1)..<featurePrints.count {
                guard !visited.contains(featurePrints[j].0.id) else { continue }

                let distance = await visionService.computeDistance(
                    between: featurePrints[i].1,
                    and: featurePrints[j].1
                )

                if distance < threshold {
                    group.append(featurePrints[j].0)
                    visited.insert(featurePrints[j].0.id)
                }
            }

            if group.count > 1 {
                let best = selectBestAsset(from: group)
                groups.append(DuplicateGroup(
                    id: UUID().uuidString,
                    assets: group,
                    bestAssetId: best.id,
                    type: .visual
                ))
            }

            progress(0.7 + Float(i + 1) / Float(max(comparisons, 1)) * 0.3)
        }

        return groups.sorted { $0.assets.count > $1.assets.count }
    }

    // MARK: - Helpers

    private func selectBestAsset(from assets: [AssetSummary]) -> AssetSummary {
        // Prefer: highest resolution, then most recent, then favorited
        assets.max { a, b in
            let aScore = a.pixelWidth * a.pixelHeight
            let bScore = b.pixelWidth * b.pixelHeight
            if aScore != bScore { return aScore < bScore }
            if a.isFavorite != b.isFavorite { return !a.isFavorite }
            return (a.creationDate ?? .distantPast) < (b.creationDate ?? .distantPast)
        } ?? assets[0]
    }

    private func loadCGImage(for assetId: String) async -> CGImage? {
        guard let uiImage = await photoService.loadThumbnail(for: assetId, size: CGSize(width: 300, height: 300)) else {
            return nil
        }
        return uiImage.cgImage
    }
}
