import SwiftUI
import SwiftData

struct ScreenshotCleanerView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ScreenshotCleanerViewModel()
    @State private var showDeleteConfirm = false
    @State private var selectedSwipeRoute: SwipeSessionRoute?
    @State private var previewAsset: AssetSummary?

    private let photoService = PhotoLibraryService()

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.xs),
        GridItem(.flexible(), spacing: Spacing.xs),
        GridItem(.flexible(), spacing: Spacing.xs)
    ]

    var body: some View {
        Group {
            if viewModel.isLoading {
                ScrollView {
                    SkeletonGrid(columns: 3, rows: 5)
                        .padding(Spacing.xs)
                }
            } else if viewModel.screenshots.isEmpty {
                EmptyStateView(
                    icon: "camera.viewfinder",
                    title: "No Screenshots",
                    message: "You don't have any screenshots in your library."
                )
            } else {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("\(viewModel.screenshots.count) screenshots \u{00B7} \(viewModel.totalSize.formattedFileSize)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Review with Swipe") {
                            HapticHelper.impact(.light)
                            startSwipeReview(with: .screenshots)
                        }
                        .font(.caption.bold())

                        Picker("Sort", selection: $viewModel.sortOrder) {
                            ForEach(ScreenshotSortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)

                    ScrollView {
                        LazyVGrid(columns: columns, spacing: Spacing.xs) {
                            ForEach(viewModel.sortedScreenshots) { screenshot in
                                screenshotCell(screenshot)
                            }
                        }
                    }

                    // Bottom action bar
                    if viewModel.isSelectionMode && !viewModel.selectedIds.isEmpty {
                        ActionBarView {
                            Text("\(viewModel.selectedIds.count) selected \u{00B7} \(viewModel.selectedSize.formattedFileSize)")
                                .font(.caption)

                            Spacer()

                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .font(.headline)
                            }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isLoading)
        .navigationTitle("Screenshots")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !viewModel.screenshots.isEmpty {
                    HStack(spacing: Spacing.md) {
                        Button {
                            HapticHelper.impact(.light)
                            startSwipeReview(with: .screenshots)
                        } label: {
                            Image(systemName: "hand.draw")
                        }

                        Button(viewModel.isSelectionMode ? "Done" : "Select") {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                viewModel.isSelectionMode.toggle()
                                if !viewModel.isSelectionMode {
                                    viewModel.deselectAll()
                                }
                            }
                        }
                    }
                }
            }
            if viewModel.isSelectionMode {
                ToolbarItem(placement: .topBarLeading) {
                    Button(viewModel.selectedIds.count == viewModel.screenshots.count ? "Deselect All" : "Select All") {
                        if viewModel.selectedIds.count == viewModel.screenshots.count {
                            viewModel.deselectAll()
                        } else {
                            viewModel.selectAll()
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
        .alert("Delete Screenshots", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(viewModel.selectedIds.count) Screenshots", role: .destructive) {
                Task { await viewModel.deleteSelected() }
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Screenshot Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(item: $previewAsset) { asset in
            ScreenshotPreviewView(
                asset: asset,
                photoService: photoService,
                onReviewWithSwipe: {
                    previewAsset = nil
                    startSwipeReview(with: .screenshots)
                },
                onDelete: {
                    Task {
                        await viewModel.delete(assetId: asset.id)
                        previewAsset = nil
                    }
                }
            )
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    private func startSwipeReview(with filter: SwipeFilter) {
        selectedSwipeRoute = SwipeSessionRoute(filter: filter)
    }

    private func screenshotCell(_ screenshot: AssetSummary) -> some View {
        ZStack(alignment: .topTrailing) {
            AsyncThumbnailView(assetId: screenshot.id, photoService: photoService)
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Spacing.xs))

            if viewModel.isSelectionMode {
                Button {
                    HapticHelper.selection()
                    viewModel.toggleSelection(screenshot.id)
                } label: {
                    Image(systemName: viewModel.selectedIds.contains(screenshot.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(viewModel.selectedIds.contains(screenshot.id) ? .blue : .white)
                        .shadow(color: .black.opacity(0.4), radius: 3)
                        .padding(Spacing.sm)
                        .scaleEffect(viewModel.selectedIds.contains(screenshot.id) ? 1.0 : 0.9)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: viewModel.selectedIds.contains(screenshot.id))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.selectedIds.contains(screenshot.id) ? "Deselect screenshot" : "Select screenshot")
                .accessibilityAddTraits(viewModel.selectedIds.contains(screenshot.id) ? [.isButton, .isSelected] : .isButton)
            }
        }
        .overlay {
            if viewModel.isSelectionMode && viewModel.selectedIds.contains(screenshot.id) {
                RoundedRectangle(cornerRadius: Spacing.xs)
                    .strokeBorder(Color.blue, lineWidth: 2)
            }
        }
        .onTapGesture {
            if viewModel.isSelectionMode {
                HapticHelper.selection()
                viewModel.toggleSelection(screenshot.id)
            } else {
                previewAsset = screenshot
            }
        }
    }
}

private struct ScreenshotPreviewView: View {
    let asset: AssetSummary
    let photoService: PhotoLibraryService
    let onReviewWithSwipe: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                AsyncThumbnailView(
                    assetId: asset.id,
                    photoService: photoService,
                    targetSize: CGSize(width: 1200, height: 1200)
                )
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
                .padding(.horizontal, Spacing.lg)

                VStack(spacing: Spacing.sm) {
                    if let filename = asset.filename, !filename.isEmpty {
                        metadataRow("Filename", value: filename)
                    }
                    metadataRow("Size", value: asset.formattedFileSize)
                    if let date = asset.creationDate {
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
                        Text("Delete Screenshot")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(Spacing.lg)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.lg)
            }
            .navigationTitle("Screenshot")
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
