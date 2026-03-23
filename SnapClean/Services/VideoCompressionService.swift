import AVFoundation
import Photos
import UIKit

struct CompressionPreset: Identifiable, Sendable {
    let id: String
    let label: String
    let preset: String
    let description: String

    static let presets: [CompressionPreset] = [
        CompressionPreset(id: "1080p", label: "1080p HD", preset: AVAssetExportPreset1920x1080, description: "Good quality, moderate savings"),
        CompressionPreset(id: "720p", label: "720p", preset: AVAssetExportPreset1280x720, description: "Decent quality, major savings"),
        CompressionPreset(id: "480p", label: "480p", preset: AVAssetExportPreset640x480, description: "Lower quality, maximum savings")
    ]
}

struct CompressionProgress: Sendable {
    let assetId: String
    let progress: Float
    let state: CompressionState
}

enum CompressionState: Sendable {
    case waiting
    case exporting(Float)
    case saving
    case completed(savedBytes: Int64)
    case failed(String)
}

actor VideoCompressionService {
    private let photoService: PhotoLibraryService

    init(photoService: PhotoLibraryService) {
        self.photoService = photoService
    }

    // MARK: - Estimate Compressed Size

    func estimateCompressedSize(for asset: AssetSummary, preset: CompressionPreset) -> Int64 {
        // Rough estimation based on target bitrate and duration
        let bitrate: Int64
        switch preset.id {
        case "1080p": bitrate = 8_000_000  // 8 Mbps
        case "720p": bitrate = 4_000_000   // 4 Mbps
        case "480p": bitrate = 2_000_000   // 2 Mbps
        default: bitrate = 6_000_000
        }

        let estimatedBytes = (bitrate / 8) * Int64(max(asset.duration, 1))
        return estimatedBytes
    }

    // MARK: - Compress Video

    func compressVideo(
        assetId: String,
        preset: CompressionPreset,
        onProgress: @escaping @Sendable (Float) -> Void
    ) async throws -> (originalSize: Int64, compressedSize: Int64, replacementAssetIdentifier: String?) {
        // Get PHAsset
        guard let phAsset = await photoService.getPHAsset(for: assetId) else {
            throw CompressionError.assetNotFound
        }

        // Get AVAsset
        let avAsset = try await loadAVAsset(from: phAsset)

        // Get original size
        let originalSize = await getFileSize(for: phAsset)

        // Export to temp file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        guard let exportSession = AVAssetExportSession(asset: avAsset, presetName: preset.preset) else {
            throw CompressionError.exportSessionCreationFailed
        }

        exportSession.outputURL = tempURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        // Monitor progress
        let progressTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                onProgress(exportSession.progress)
            }
        }

        await exportSession.export()
        progressTask.cancel()

        guard exportSession.status == .completed else {
            try? FileManager.default.removeItem(at: tempURL)
            throw CompressionError.exportFailed(exportSession.error?.localizedDescription ?? "Unknown error")
        }

        // Get compressed size
        let compressedSize: Int64
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
            compressedSize = (attrs[.size] as? Int64) ?? 0
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw CompressionError.fileSizeReadFailed
        }

        // Save compressed video to photo library
        var placeholder: PHObjectPlaceholder?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempURL)
            placeholder = request?.placeholderForCreatedAsset
        }

        // Verify the compressed video was actually created before deleting original
        guard placeholder?.localIdentifier != nil else {
            try? FileManager.default.removeItem(at: tempURL)
            throw CompressionError.exportFailed("Failed to save compressed video to library")
        }

        // Delete original only after confirming new asset was created
        try await photoService.deleteAssets(identifiers: [assetId])

        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)

        return (
            originalSize: originalSize,
            compressedSize: compressedSize,
            replacementAssetIdentifier: placeholder?.localIdentifier
        )
    }

    // MARK: - Helpers

    private func loadAVAsset(from phAsset: PHAsset) async throws -> AVAsset {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            nonisolated(unsafe) var hasResumed = false
            PHImageManager.default().requestAVAsset(
                forVideo: phAsset,
                options: options
            ) { avAsset, _, info in
                guard !hasResumed else { return }
                hasResumed = true
                if let avAsset {
                    continuation.resume(returning: avAsset)
                } else {
                    continuation.resume(throwing: CompressionError.videoLoadFailed)
                }
            }
        }
    }

    private func getFileSize(for asset: PHAsset) async -> Int64 {
        let resources = PHAssetResource.assetResources(for: asset)
        var total: Int64 = 0
        for resource in resources {
            if resource.responds(to: Selector(("fileSize"))),
               let size = resource.value(forKey: "fileSize") as? Int64 {
                total += size
            }
        }
        return total
    }
}

enum CompressionError: LocalizedError {
    case assetNotFound
    case videoLoadFailed
    case exportSessionCreationFailed
    case exportFailed(String)
    case fileSizeReadFailed

    var errorDescription: String? {
        switch self {
        case .assetNotFound: "Video not found."
        case .videoLoadFailed: "Failed to load video."
        case .exportSessionCreationFailed: "Failed to create export session."
        case .exportFailed(let msg): "Export failed: \(msg)"
        case .fileSizeReadFailed: "Failed to read file size."
        }
    }
}
