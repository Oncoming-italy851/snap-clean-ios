import SwiftUI

struct RecentlyDeletedView: View {
    @State private var viewModel = RecentlyDeletedViewModel()
    @State private var showDeleteAllConfirm = false
    @State private var showDeleteSelectedConfirm = false
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
            } else if !viewModel.isAccessible {
                inaccessibleView
            } else {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("\(viewModel.assets.count) items")
                                .font(.headline)
                            Text(viewModel.totalSize.formattedFileSize)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) { showDeleteAllConfirm = true } label: {
                            Text("Delete All")
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.md)

                    ScrollView {
                        LazyVGrid(columns: columns, spacing: Spacing.xs) {
                            ForEach(viewModel.assets) { asset in
                                assetCell(asset)
                            }
                        }
                    }

                    if viewModel.isSelectionMode && !viewModel.selectedIds.isEmpty {
                        ActionBarView {
                            Text("\(viewModel.selectedIds.count) selected \u{00B7} \(viewModel.selectedSize.formattedFileSize)")
                                .font(.caption)
                            Spacer()
                            Button(role: .destructive) { showDeleteSelectedConfirm = true } label: {
                                Label("Delete Permanently", systemImage: "trash")
                                    .font(.headline)
                            }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isLoading)
        .navigationTitle("Recently Deleted")
        .toolbar {
            if !viewModel.assets.isEmpty {
                if viewModel.isSelectionMode {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(viewModel.selectedIds.count == viewModel.assets.count ? "Deselect All" : "Select All") {
                            if viewModel.selectedIds.count == viewModel.assets.count {
                                viewModel.deselectAll()
                            } else {
                                viewModel.selectAll()
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(viewModel.isSelectionMode ? "Done" : "Select") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            viewModel.isSelectionMode.toggle()
                            if !viewModel.isSelectionMode { viewModel.deselectAll() }
                        }
                    }
                }
            }
        }
        .alert("Delete All Permanently", isPresented: $showDeleteAllConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                Task { await viewModel.deleteAll() }
            }
        } message: {
            Text("This will permanently delete all \(viewModel.assets.count) items (\(viewModel.totalSize.formattedFileSize)). This cannot be undone.")
        }
        .alert("Delete Selected", isPresented: $showDeleteSelectedConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(viewModel.selectedIds.count) Items", role: .destructive) {
                Task { await viewModel.deleteSelected() }
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Recently Deleted Error", isPresented: .init(
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

    private func assetCell(_ asset: AssetSummary) -> some View {
        ZStack(alignment: .topTrailing) {
            AsyncThumbnailView(assetId: asset.id, photoService: photoService)
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Spacing.xs))

            if viewModel.isSelectionMode {
                Button {
                    HapticHelper.selection()
                    viewModel.toggleSelection(asset.id)
                } label: {
                    Image(systemName: viewModel.selectedIds.contains(asset.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(viewModel.selectedIds.contains(asset.id) ? .blue : .white)
                        .shadow(color: .black.opacity(0.4), radius: 3)
                        .padding(Spacing.sm)
                        .scaleEffect(viewModel.selectedIds.contains(asset.id) ? 1.0 : 0.9)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: viewModel.selectedIds.contains(asset.id))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.selectedIds.contains(asset.id) ? "Deselect item" : "Select item")
                .accessibilityAddTraits(viewModel.selectedIds.contains(asset.id) ? [.isButton, .isSelected] : .isButton)
            }

            if asset.mediaType == .video {
                VStack {
                    Spacer()
                    HStack {
                        Text(asset.formattedDuration)
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small / 2))
                        Spacer()
                    }
                    .padding(Spacing.xs)
                }
            }
        }
        .overlay {
            if viewModel.isSelectionMode && viewModel.selectedIds.contains(asset.id) {
                RoundedRectangle(cornerRadius: Spacing.xs)
                    .strokeBorder(Color.blue, lineWidth: 2)
            }
        }
        .onTapGesture {
            guard viewModel.isSelectionMode else { return }
            HapticHelper.selection()
            viewModel.toggleSelection(asset.id)
        }
    }

    private var inaccessibleView: some View {
        EmptyStateView(
            icon: "lock.shield",
            title: "Use Photos to Empty Recently Deleted",
            message: "iOS does not expose the Recently Deleted album through a stable public API. Open Photos → Albums → Recently Deleted to review or permanently delete those items."
        )
    }
}
