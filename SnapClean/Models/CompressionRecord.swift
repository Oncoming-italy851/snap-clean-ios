import Foundation
import SwiftData

@Model
final class CompressionRecord {
    var assetLocalIdentifier: String
    var replacementAssetLocalIdentifier: String?
    var originalSizeBytes: Int64
    var compressedSizeBytes: Int64
    var compressedAt: Date
    var exportPreset: String
    var outcome: String

    init(
        assetLocalIdentifier: String,
        replacementAssetLocalIdentifier: String? = nil,
        originalSizeBytes: Int64,
        compressedSizeBytes: Int64,
        compressedAt: Date = .now,
        exportPreset: String,
        outcome: String = "completed"
    ) {
        self.assetLocalIdentifier = assetLocalIdentifier
        self.replacementAssetLocalIdentifier = replacementAssetLocalIdentifier
        self.originalSizeBytes = originalSizeBytes
        self.compressedSizeBytes = compressedSizeBytes
        self.compressedAt = compressedAt
        self.exportPreset = exportPreset
        self.outcome = outcome
    }
}
