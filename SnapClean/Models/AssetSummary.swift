import Foundation

enum MediaType: String, Sendable {
    case photo
    case video
    case audio
    case unknown
}

struct AssetSummary: Identifiable, Sendable, Hashable {
    let id: String
    let mediaType: MediaType
    let creationDate: Date?
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: TimeInterval
    let fileSize: Int64
    let filename: String?
    let isFavorite: Bool
    let isBurst: Bool
    let burstIdentifier: String?
    let isLivePhoto: Bool
    let isScreenshot: Bool
    let isLocallyAvailable: Bool

    var resolution: String {
        "\(pixelWidth) × \(pixelHeight)"
    }

    var formattedDuration: String {
        guard duration > 0 else { return "" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}
