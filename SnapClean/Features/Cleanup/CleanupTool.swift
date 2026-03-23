import SwiftUI

enum CleanupTool: String, CaseIterable, Identifiable, Hashable, Sendable {
    case duplicates
    case similar
    case screenshots
    case blurry
    case largeFiles
    case bursts
    case livePhotos
    case videoCompression
    case recentlyDeleted

    var id: String { rawValue }

    var name: String {
        switch self {
        case .duplicates: "Duplicates"
        case .similar: "Similar Photos"
        case .screenshots: "Screenshots"
        case .blurry: "Blurry Photos"
        case .largeFiles: "Large Files"
        case .bursts: "Burst Photos"
        case .livePhotos: "Live Photos"
        case .videoCompression: "Video Compression"
        case .recentlyDeleted: "Recently Deleted"
        }
    }

    var description: String {
        switch self {
        case .duplicates: "Find exact & visual duplicates"
        case .similar: "Photos taken close together"
        case .screenshots: "Review & clean up screenshots"
        case .blurry: "Out-of-focus & poorly lit"
        case .largeFiles: "Biggest files in your library"
        case .bursts: "Clean up burst sequences"
        case .livePhotos: "Convert to stills & save space"
        case .videoCompression: "Compress videos to save space"
        case .recentlyDeleted: "Guidance for purging deleted items in Photos"
        }
    }

    var icon: String {
        switch self {
        case .duplicates: "doc.on.doc"
        case .similar: "square.on.square"
        case .screenshots: "camera.viewfinder"
        case .blurry: "camera.metering.unknown"
        case .largeFiles: "externaldrive"
        case .bursts: "square.stack.3d.up"
        case .livePhotos: "livephoto"
        case .videoCompression: "video.badge.waveform"
        case .recentlyDeleted: "trash"
        }
    }

    var color: Color {
        switch self {
        case .duplicates: .red
        case .similar: .orange
        case .screenshots: .yellow
        case .blurry: .purple
        case .largeFiles: .blue
        case .bursts: .teal
        case .livePhotos: .green
        case .videoCompression: .indigo
        case .recentlyDeleted: .gray
        }
    }
}

@ViewBuilder
func cleanupDestinationView(for tool: CleanupTool) -> some View {
    switch tool {
    case .duplicates:
        DuplicateFinderView()
    case .similar:
        SimilarPhotosView()
    case .screenshots:
        ScreenshotCleanerView()
    case .blurry:
        BlurryPhotosView()
    case .largeFiles:
        LargeFilesView()
    case .bursts:
        BurstCleanerView()
    case .livePhotos:
        LivePhotosConverterView()
    case .videoCompression:
        VideoCompressionView()
    case .recentlyDeleted:
        RecentlyDeletedView()
    }
}
