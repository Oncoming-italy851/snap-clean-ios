import SwiftUI

struct SimilarGroupDetailView: View {
    @State private var group: SimilarGroup
    @Binding var selectedForDeletion: Set<String>
    let onSetBest: (String, String) -> Void

    @State private var currentPage = 0
    @State private var albumNames: [String: [String]] = [:]

    private let photoService = PhotoLibraryService()

    init(
        group: SimilarGroup,
        selectedForDeletion: Binding<Set<String>>,
        onSetBest: @escaping (String, String) -> Void
    ) {
        _group = State(initialValue: group)
        _selectedForDeletion = selectedForDeletion
        self.onSetBest = onSetBest
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(Array(group.assets.enumerated()), id: \.element.id) { index, asset in
                    assetDetailCard(asset)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(maxHeight: .infinity)

            ActionBarView {
                let currentAsset = group.assets[safe: currentPage]
                let isBest = currentAsset?.id == group.bestAssetId

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("\(currentPage + 1) of \(group.assets.count)")
                        .font(.caption.bold())
                    Text(isBest ? "Best photo" : "Review keep/delete choice")
                        .font(.caption)
                        .foregroundStyle(isBest ? .green : .secondary)
                }

                Spacer()

                if let currentAsset, !isBest {
                    Button {
                        HapticHelper.selection()
                        let oldBest = group.bestAssetId
                        group = SimilarGroup(
                            id: group.id,
                            assets: group.assets,
                            bestAssetId: currentAsset.id
                        )
                        selectedForDeletion.remove(currentAsset.id)
                        if oldBest != currentAsset.id {
                            selectedForDeletion.insert(oldBest)
                        }
                        onSetBest(currentAsset.id, group.id)
                    } label: {
                        Text("Keep This Best")
                            .font(.headline)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                            .background(.green)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    }
                    .scaleOnPress()

                    Button {
                        HapticHelper.selection()
                        if selectedForDeletion.contains(currentAsset.id) {
                            selectedForDeletion.remove(currentAsset.id)
                        } else {
                            selectedForDeletion.insert(currentAsset.id)
                        }
                    } label: {
                        Text(selectedForDeletion.contains(currentAsset.id) ? "Keep This" : "Mark Delete")
                            .font(.headline)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                            .background(selectedForDeletion.contains(currentAsset.id) ? .gray : .red)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    }
                    .scaleOnPress()
                }
            }
        }
        .navigationTitle("Review Group")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            for asset in group.assets {
                let names = await photoService.albumsContaining(assetId: asset.id)
                albumNames[asset.id] = names
            }
        }
    }

    private func assetDetailCard(_ asset: AssetSummary) -> some View {
        VStack(spacing: 0) {
            AsyncThumbnailView(
                assetId: asset.id,
                photoService: photoService,
                targetSize: CGSize(width: 600, height: 600)
            )
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            .overlay(alignment: .topTrailing) {
                if asset.id == group.bestAssetId {
                    statusPill(icon: "star.fill", text: "Best", color: .green)
                } else if selectedForDeletion.contains(asset.id) {
                    statusPill(icon: "trash.fill", text: "Delete", color: .red)
                }
            }
            .padding(.horizontal, Spacing.lg)

            VStack(spacing: Spacing.sm) {
                metadataRow("Resolution", value: asset.resolution)
                metadataRow("File Size", value: asset.formattedFileSize)
                if let date = asset.creationDate {
                    metadataRow("Date", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                if let names = albumNames[asset.id], !names.isEmpty {
                    metadataRow("Albums", value: names.joined(separator: ", "))
                } else {
                    metadataRow("Albums", value: "None")
                }
            }
            .glassCard()
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
        }
    }

    private func statusPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption.bold())
        .foregroundStyle(.white)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(color.opacity(0.85))
        .clipShape(Capsule())
        .padding(Spacing.sm)
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
