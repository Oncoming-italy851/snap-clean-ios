import SwiftUI
import SwiftData

struct VideoCompressionView: View {
    @State private var viewModel = VideoCompressionViewModel()
    @State private var showCompressConfirm = false
    @Environment(\.modelContext) private var modelContext
    private let photoService = PhotoLibraryService()

    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if viewModel.videos.isEmpty {
                EmptyStateView(
                    icon: "video.badge.waveform",
                    title: "No Videos",
                    message: "You don't have any videos in your library.",
                    iconColor: .purple
                )
            } else {
                contentView
            }
        }
        .navigationTitle("Video Compression")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: Spacing.md) {
                    NavigationLink {
                        CompressionHistoryView()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }

                    if !viewModel.videos.isEmpty {
                        Button(viewModel.isSelectionMode ? "Done" : "Select") {
                            HapticHelper.impact(.light)
                            viewModel.isSelectionMode.toggle()
                            if !viewModel.isSelectionMode {
                                viewModel.selectedIds.removeAll()
                            }
                        }
                        .disabled(viewModel.isCompressing)
                    }
                }
            }
        }
        .alert("Compress Videos", isPresented: $showCompressConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Compress \(viewModel.selectedIds.count) Videos", role: .destructive) {
                Task {
                    await viewModel.compressSelected(modelContext: modelContext)
                    HapticHelper.notification(.success)
                }
            }
        } message: {
            Text("This will replace the original videos with compressed versions. This action cannot be undone.")
        }
        .alert("Compression Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        List {
            ForEach(0..<6, id: \.self) { _ in
                SkeletonRow()
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
    }

    // MARK: - Content View

    private var contentView: some View {
        VStack(spacing: 0) {
            List {
                ForEach(Array(viewModel.sortedVideos.enumerated()), id: \.element.id) { index, video in
                    videoRow(video)
                        .fadeSlideIn(delay: Double(index) * 0.03)
                }
            }
            .listStyle(.plain)

            if !viewModel.selectedIds.isEmpty {
                bottomBar
            }
        }
    }

    // MARK: - Video Row

    private func videoRow(_ video: VideoItem) -> some View {
        HStack(spacing: Spacing.md) {
            if viewModel.isSelectionMode {
                Button {
                    HapticHelper.selection()
                    viewModel.toggleSelection(video.id)
                } label: {
                    Image(systemName: viewModel.selectedIds.contains(video.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(viewModel.selectedIds.contains(video.id) ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.selectedIds.contains(video.id) ? "Deselect video" : "Select video")
                .accessibilityAddTraits(viewModel.selectedIds.contains(video.id) ? [.isButton, .isSelected] : .isButton)
            }

            AsyncThumbnailView(assetId: video.id, photoService: photoService)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                .overlay(alignment: .bottomLeading) {
                    Text(video.asset.formattedDuration)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.xs))
                        .padding(Spacing.xs)
                }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                if let date = video.asset.creationDate {
                    Text(date, style: .date)
                        .font(.subheadline)
                }
                Menu {
                    ForEach(CompressionPreset.presets) { preset in
                        Button(preset.label) {
                            viewModel.setPreset(preset, for: video.id)
                        }
                    }
                } label: {
                    Text(video.selectedPreset.label)
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                }

                Text(video.asset.resolution)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                compressionStateLabel(video)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text(video.asset.formattedFileSize)
                    .font(.headline.monospacedDigit())

                let estimated = viewModel.estimateSize(for: video)
                if estimated < video.asset.fileSize {
                    Text("\u{2192} ~\(estimated.formattedFileSize)")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if viewModel.isSelectionMode {
                HapticHelper.selection()
                viewModel.toggleSelection(video.id)
            }
        }
    }

    // MARK: - Compression State Label

    @ViewBuilder
    private func compressionStateLabel(_ video: VideoItem) -> some View {
        switch video.compressionState {
        case .waiting:
            EmptyView()
        case .exporting(let progress):
            ProgressView(value: progress)
                .tint(.blue)
                .frame(width: 80)
        case .saving:
            Text("Saving...")
                .font(.caption)
                .foregroundStyle(.blue)
        case .completed(let saved):
            Text("Saved \(saved.formattedFileSize)")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let msg):
            Text(msg)
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        ActionBarView {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("\(viewModel.selectedIds.count) selected")
                    .font(.caption.bold())
                Text(viewModel.selectedSize.formattedFileSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.isCompressing {
                ProgressView()
                    .padding(.trailing, Spacing.sm)
                Text("Compressing...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    HapticHelper.impact(.light)
                    showCompressConfirm = true
                } label: {
                    Text("Compress")
                        .font(.headline)
                        .padding(.horizontal, Spacing.xxl)
                        .padding(.vertical, Spacing.sm)
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                }
                .scaleOnPress()
            }
        }
    }
}
