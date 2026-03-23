import SwiftUI
import SwiftData

struct BlurryPhotosView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = BlurryPhotosViewModel()
    @State private var showDeleteConfirm = false
    @State private var selectedSwipeRoute: SwipeSessionRoute?
    @State private var previewPhoto: AnalyzedPhoto?

    private let photoService = PhotoLibraryService()

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.xs),
        GridItem(.flexible(), spacing: Spacing.xs),
        GridItem(.flexible(), spacing: Spacing.xs)
    ]

    var body: some View {
        Group {
            switch viewModel.scanState {
            case .idle:
                idleView
                    .transition(.stateTransition)
            case .scanning(let progress):
                scanningView(progress: progress)
                    .transition(.stateTransition)
            case .completed:
                resultsView
                    .transition(.stateTransition)
            case .error(let message):
                errorView(message: message)
                    .transition(.stateTransition)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.scanState)
        .navigationTitle("Photo Quality")
        .toolbar {
            if viewModel.scanState == .completed && !viewModel.filteredPhotos.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: Spacing.md) {
                        Button {
                            HapticHelper.impact(.light)
                            let ids = Set(viewModel.filteredPhotos.map(\.id))
                            startSwipeReview(with: .customAssetIds(ids))
                        } label: {
                            Image(systemName: "hand.draw")
                        }

                        Button(viewModel.isSelectionMode ? "Done" : "Select") {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                viewModel.isSelectionMode.toggle()
                                if !viewModel.isSelectionMode { viewModel.deselectAll() }
                            }
                        }
                    }
                }
            }
        }
        .navigationDestination(item: $selectedSwipeRoute) { route in
            SwipeSessionHostView(
                route: route,
                photoService: photoService,
                modelContext: modelContext
            )
        }
        .alert("Delete Photos", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(viewModel.selectedIds.count) Photos", role: .destructive) {
                Task { await viewModel.deleteSelected() }
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Photo Quality Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(item: $previewPhoto) { photo in
            PhotoQualityPreviewView(
                photo: photo,
                photoService: photoService,
                onReviewWithSwipe: {
                    previewPhoto = nil
                    let ids = Set(viewModel.filteredPhotos.map(\.id))
                    startSwipeReview(with: .customAssetIds(ids))
                },
                onDelete: {
                    Task {
                        await viewModel.delete(assetId: photo.id)
                        previewPhoto = nil
                    }
                }
            )
        }
        .onChange(of: viewModel.activeTab) { _, _ in
            // Selections are preserved across tabs — they're just not visible
            // on other tabs. No need to clear them on tab switch.
        }
    }

    private func startSwipeReview(with filter: SwipeFilter) {
        selectedSwipeRoute = SwipeSessionRoute(filter: filter)
    }

    // MARK: - Idle View

    private var idleView: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.orange.opacity(0.15), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                Image(systemName: "camera.metering.unknown")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(Color.orange.opacity(0.8))
                    .subtleShadow()
            }
            .fadeSlideIn()

            VStack(spacing: Spacing.sm) {
                Text("Detect Low-Quality Photos")
                    .font(.title2.bold())
                Text("Find blurry, too dark, and overexposed photos.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxxl)
            }
            .fadeSlideIn(delay: 0.05)

            Button {
                HapticHelper.impact(.light)
                Task { await viewModel.scan() }
            } label: {
                Text("Start Analysis")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(Spacing.lg)
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }
            .scaleOnPress()
            .padding(.horizontal, Spacing.xxxl + Spacing.sm)
            .fadeSlideIn(delay: 0.1)

            Spacer()
        }
    }

    // MARK: - Scanning View

    private func scanningView(progress: Float) -> some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            ProgressView(value: progress) {
                Text("Analyzing photos...")
                    .font(.headline)
            } currentValueLabel: {
                Text("\(Int(progress * 100))% \u{00B7} \(viewModel.analyzedPhotos.count) issues found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Spacing.xxxl + Spacing.sm)
            Spacer()
        }
        .fadeSlideIn()
    }

    // MARK: - Results View

    private var resultsView: some View {
        VStack(spacing: 0) {
            // Tab bar
            Picker("Category", selection: $viewModel.activeTab) {
                Text("Blurry (\(viewModel.blurryCount))").tag(BlurryTab.blurry)
                Text("Dark (\(viewModel.darkCount))").tag(BlurryTab.tooDark)
                Text("Bright (\(viewModel.overexposedCount))").tag(BlurryTab.overexposed)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)

            if viewModel.filteredPhotos.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "All Clear",
                    message: "No issues found in this category.",
                    iconColor: .green
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Spacing.xs) {
                        ForEach(viewModel.filteredPhotos) { photo in
                            photoCell(photo)
                        }
                    }
                }

                if viewModel.isSelectionMode && !viewModel.selectedIds.isEmpty {
                    ActionBarView {
                        Text("\(viewModel.selectedIds.count) selected \u{00B7} \(viewModel.selectedSize.formattedFileSize)")
                            .font(.caption)
                        Spacer()
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Delete", systemImage: "trash")
                                .font(.headline)
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        EmptyStateView(
            icon: "exclamationmark.triangle",
            title: "Analysis Failed",
            message: message,
            iconColor: .red,
            actionTitle: "Retry"
        ) {
            withAnimation { viewModel.scanState = .idle }
        }
    }

    // MARK: - Photo Cell

    private func photoCell(_ photo: AnalyzedPhoto) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncThumbnailView(assetId: photo.id, photoService: photoService)
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Spacing.xs))

            // Score indicator
            HStack(spacing: Spacing.xs) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                        Rectangle()
                            .fill(scoreColor(for: viewModel.activeTab))
                            .frame(width: geo.size.width * CGFloat(scoreValue(for: photo, tab: viewModel.activeTab)))
                    }
                }
                .frame(width: 40, height: 4)
                .clipShape(Capsule())
            }
            .padding(Spacing.sm)

            if viewModel.isSelectionMode {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            HapticHelper.selection()
                            viewModel.toggleSelection(photo.id)
                        } label: {
                            Image(systemName: viewModel.selectedIds.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(viewModel.selectedIds.contains(photo.id) ? .blue : .white)
                                .shadow(color: .black.opacity(0.4), radius: 3)
                                .padding(Spacing.sm)
                                .scaleEffect(viewModel.selectedIds.contains(photo.id) ? 1.0 : 0.9)
                                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: viewModel.selectedIds.contains(photo.id))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(viewModel.selectedIds.contains(photo.id) ? "Deselect photo" : "Select photo")
                        .accessibilityAddTraits(viewModel.selectedIds.contains(photo.id) ? [.isButton, .isSelected] : .isButton)
                    }
                    Spacer()
                }
            }
        }
        .overlay {
            if viewModel.isSelectionMode && viewModel.selectedIds.contains(photo.id) {
                RoundedRectangle(cornerRadius: Spacing.xs)
                    .strokeBorder(Color.blue, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if viewModel.isSelectionMode {
                HapticHelper.selection()
                viewModel.toggleSelection(photo.id)
            } else {
                previewPhoto = photo
            }
        }
    }

    private func scoreColor(for tab: BlurryTab) -> Color {
        switch tab {
        case .blurry: return .orange
        case .tooDark: return .purple
        case .overexposed: return .yellow
        }
    }

    private func scoreValue(for photo: AnalyzedPhoto, tab: BlurryTab) -> Float {
        switch tab {
        case .blurry:
            return photo.blurScore
        case .tooDark:
            return max(0, min(1, 1 - photo.luminance))
        case .overexposed:
            return photo.luminance
        }
    }
}

private struct PhotoQualityPreviewView: View {
    let photo: AnalyzedPhoto
    let photoService: PhotoLibraryService
    let onReviewWithSwipe: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                AsyncThumbnailView(
                    assetId: photo.id,
                    photoService: photoService,
                    targetSize: CGSize(width: 1200, height: 1200)
                )
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
                .padding(.horizontal, Spacing.lg)

                VStack(spacing: Spacing.sm) {
                    metadataRow("Size", value: photo.asset.formattedFileSize)
                    metadataRow("Resolution", value: photo.asset.resolution)
                    metadataRow("Blur Score", value: String(format: "%.2f", photo.blurScore))
                    metadataRow("Luminance", value: String(format: "%.2f", photo.luminance))
                    if let date = photo.asset.creationDate {
                        metadataRow("Captured", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                .glassCard()
                .padding(.horizontal, Spacing.lg)

                Spacer()

                VStack(spacing: Spacing.sm) {
                    Button {
                        dismiss()
                        onReviewWithSwipe()
                    } label: {
                        Text("Review with Swipe")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(Spacing.lg)
                            .background(.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    }

                    Button(role: .destructive) {
                        dismiss()
                        onDelete()
                    } label: {
                        Text("Delete Photo")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(Spacing.lg)
                            .background(Color.destructive)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.lg)
            }
            .navigationTitle("Photo Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
                .multilineTextAlignment(.trailing)
        }
    }
}
