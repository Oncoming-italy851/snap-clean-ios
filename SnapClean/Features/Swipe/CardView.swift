import SwiftUI

struct CardView: View {
    let asset: AssetSummary
    let photoService: PhotoLibraryService
    let isTopCard: Bool

    @State private var image: UIImage?
    @State private var isLoadingImage = true
    @State private var downloadProgress: Double?

    var dragOffset: CGSize = .zero

    private var deleteOpacity: Double {
        guard isTopCard else { return 0 }
        return min(max(-Double(dragOffset.width) / 150.0, 0), 1.0)
    }

    private var keepOpacity: Double {
        guard isTopCard else { return 0 }
        return min(max(Double(dragOffset.width) / 150.0, 0), 1.0)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Image
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .transition(.opacity)
                } else {
                    SkeletonView(cornerRadius: 0)
                }

                // Gradient overlay at bottom
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 140)
                }

                // Metadata overlay
                VStack {
                    // Top badges
                    HStack(spacing: Spacing.sm) {
                        if asset.isLivePhoto {
                            BadgeView(text: "LIVE", icon: "livephoto", color: .yellow)
                        }
                        if !asset.isLocallyAvailable {
                            if let progress = downloadProgress {
                                // Download progress indicator
                                HStack(spacing: Spacing.xs) {
                                    ZStack {
                                        Circle()
                                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                        Circle()
                                            .trim(from: 0, to: progress)
                                            .stroke(Color.blue, lineWidth: 2)
                                            .rotationEffect(.degrees(-90))
                                    }
                                    .frame(width: 16, height: 16)

                                    Text("\(Int(progress * 100))%")
                                        .font(.caption2.bold())
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xs)
                                .background(.blue.opacity(0.7))
                                .clipShape(Capsule())
                            } else {
                                BadgeView(text: "iCloud", icon: "icloud.and.arrow.down", color: .blue)
                            }
                        }
                        Spacer()
                    }
                    .padding(.top, Spacing.lg)
                    .padding(.horizontal, Spacing.lg)

                    Spacer()

                    // Bottom info
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            if asset.mediaType == .video {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: "video.fill")
                                        .font(.caption)
                                    Text(asset.formattedDuration)
                                        .font(.caption.monospacedDigit())
                                }
                                .foregroundStyle(.white)
                            }

                            if let date = asset.creationDate {
                                Text(date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }

                        Spacer()

                        Text(asset.formattedFileSize)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.lg)
                }

                // Swipe indicators
                if isTopCard {
                    VStack {
                        HStack {
                            Spacer()
                            Text("DELETE")
                                .font(.title.bold())
                                .foregroundStyle(.red)
                                .padding(.horizontal, Spacing.lg)
                                .padding(.vertical, Spacing.sm)
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.small)
                                        .stroke(.red, lineWidth: 3)
                                )
                                .rotationEffect(.degrees(15))
                                .padding(.trailing, Spacing.xxl)
                                .padding(.top, 40)
                        }
                        Spacer()
                    }
                    .opacity(deleteOpacity)

                    VStack {
                        HStack {
                            Text("KEEP")
                                .font(.title.bold())
                                .foregroundStyle(.green)
                                .padding(.horizontal, Spacing.lg)
                                .padding(.vertical, Spacing.sm)
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.small)
                                        .stroke(.green, lineWidth: 3)
                                )
                                .rotationEffect(.degrees(-15))
                                .padding(.leading, Spacing.xxl)
                                .padding(.top, 40)
                            Spacer()
                        }
                        Spacer()
                    }
                    .opacity(keepOpacity)

                    Rectangle()
                        .fill(.red.opacity(deleteOpacity * 0.15))
                    Rectangle()
                        .fill(.green.opacity(keepOpacity * 0.15))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
            .cardShadow()
        }
        .task {
            await loadImage()
        }
    }

    private func loadImage() async {
        isLoadingImage = true
        let screenSize = UIScreen.main.bounds.size
        let targetSize = CGSize(
            width: screenSize.width * UIScreen.main.scale,
            height: screenSize.height * UIScreen.main.scale
        )
        let loaded = await photoService.loadImage(for: asset.id, targetSize: targetSize)
        withAnimation(.easeIn(duration: 0.3)) {
            image = loaded
        }
        isLoadingImage = false
    }
}

struct BadgeView: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2.bold())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(color.opacity(0.7))
        .clipShape(Capsule())
    }
}
