import Foundation
import SwiftData

@Model
final class StorageSnapshot {
    var capturedAt: Date
    var photoBytes: Int64
    var videoBytes: Int64
    var screenshotBytes: Int64
    var otherBytes: Int64

    var totalBytes: Int64 {
        photoBytes + videoBytes + screenshotBytes + otherBytes
    }

    init(capturedAt: Date = .now, photoBytes: Int64, videoBytes: Int64, screenshotBytes: Int64, otherBytes: Int64) {
        self.capturedAt = capturedAt
        self.photoBytes = photoBytes
        self.videoBytes = videoBytes
        self.screenshotBytes = screenshotBytes
        self.otherBytes = otherBytes
    }
}
