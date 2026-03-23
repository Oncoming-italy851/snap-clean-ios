import SwiftUI

struct LargeFilesView: View {
    @State private var viewModel = LargeFilesViewModel()
    @State private var showDeleteConfirm = false
    private let photoService = PhotoLibraryService()

    var body: some View {
        Group {
            if viewModel.isLoading {
                List {
                    ForEach(0..<8, id: \.self) { _ in
                        SkeletonRow()
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            } else if viewModel.filteredAssets.isEmpty {
                EmptyStateView(
                    icon: "externaldrive",
                    title: "No Large Files",
                    message: "No files larger than \(Int(viewModel.thresholdMB)) MB found."
                )
            } else {
                VStack(spacing: 0) {
                    // Controls
                    VStack(spacing: Spacing.sm) {
                        HStack {
                            Text("Min size: \(Int(viewModel.thresholdMB)) MB")
                                .font(.caption)
                            Spacer()
                            Text("\(viewModel.filteredAssets.count) files \u{00B7} \(viewModel.totalSize.formattedFileSize)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $viewModel.thresholdMB, in: 5...500, step: 5)

                        Picker("Filter", selection: $viewModel.mediaFilter) {
                            ForEach(LargeFileFilter.allCases, id: \.self) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker("Sort", selection: $viewModel.sortOrder) {
                            ForEach(LargeFileSortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(Spacing.lg)

                    List {
                        ForEach(viewModel.filteredAssets) { asset in
                            fileRow(asset)
                        }
                    }
                    .listStyle(.plain)

                    if viewModel.isSelectionMode && !viewModel.selectedIds.isEmpty {
                        ActionBarView {
                            Text("\(viewModel.selectedVisibleCount) selected \u{00B7} \(viewModel.selectedSize.formattedFileSize)")
                                .font(.caption)
                            Spacer()
                            Button(role: .destructive) { showDeleteConfirm = true } label: {
                                Text("Delete \(viewModel.selectedVisibleCount) items \u{00B7} \(viewModel.selectedSize.formattedFileSize)")
                                    .font(.headline)
                            }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isLoading)
        .navigationTitle("Large Files")
        .toolbar {
            if !viewModel.filteredAssets.isEmpty {
                if viewModel.isSelectionMode {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(viewModel.areAllVisibleSelected ? "Deselect All" : "Select All") {
                            if viewModel.areAllVisibleSelected {
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
        .alert("Delete Files", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(viewModel.selectedVisibleCount) Files", role: .destructive) {
                Task { await viewModel.deleteSelected() }
            }
        } message: {
            Text("This will delete \(viewModel.selectedSize.formattedFileSize) of media. This action cannot be undone.")
        }
        .alert("Large Files Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onChange(of: viewModel.thresholdMB) { _, _ in
            viewModel.synchronizeSelection()
        }
        .onChange(of: viewModel.mediaFilter) { _, _ in
            viewModel.synchronizeSelection()
        }
        .onChange(of: viewModel.sortOrder) { _, _ in
            viewModel.synchronizeSelection()
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    private func fileRow(_ asset: AssetSummary) -> some View {
        HStack(spacing: Spacing.md) {
            if viewModel.isSelectionMode {
                Button {
                    HapticHelper.selection()
                    viewModel.toggleSelection(asset.id)
                } label: {
                    Image(systemName: viewModel.selectedIds.contains(asset.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(viewModel.selectedIds.contains(asset.id) ? .blue : .secondary)
                        .scaleEffect(viewModel.selectedIds.contains(asset.id) ? 1.0 : 0.9)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: viewModel.selectedIds.contains(asset.id))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.selectedIds.contains(asset.id) ? "Deselect file" : "Select file")
                .accessibilityAddTraits(viewModel.selectedIds.contains(asset.id) ? [.isButton, .isSelected] : .isButton)
            }

            AsyncThumbnailView(assetId: asset.id, photoService: photoService)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))

            VStack(alignment: .leading, spacing: Spacing.xs) {
                if let filename = asset.filename, !filename.isEmpty {
                    Text(filename)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                }
                HStack(spacing: Spacing.xs) {
                    Image(systemName: asset.mediaType == .video ? "video" : "photo")
                        .font(.caption)
                    if let date = asset.creationDate {
                        Text(date, style: .date)
                            .font(.subheadline)
                    }
                }

                Text(asset.resolution)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if asset.mediaType == .video {
                    Text(asset.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(asset.formattedFileSize)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if viewModel.isSelectionMode {
                HapticHelper.selection()
                viewModel.toggleSelection(asset.id)
            }
        }
    }
}
