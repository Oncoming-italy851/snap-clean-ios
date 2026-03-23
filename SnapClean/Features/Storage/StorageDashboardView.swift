import SwiftUI
import Charts

struct StorageDashboardView: View {
    @State private var viewModel = StorageDashboardViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigation.self) private var appNavigation

    var body: some View {
        ScrollView {
            if viewModel.isLoading {
                VStack(spacing: Spacing.lg) {
                    ForEach(0..<4, id: \.self) { _ in
                        SkeletonCard()
                    }
                }
                .padding(Spacing.lg)
            } else {
                VStack(spacing: Spacing.xl) {
                    storageBreakdownSection
                        .fadeSlideIn(delay: 0.0)
                    deviceStorageSection
                        .fadeSlideIn(delay: 0.1)
                    iCloudSection
                        .fadeSlideIn(delay: 0.15)
                    trendSection
                        .fadeSlideIn(delay: 0.2)
                    cleanupOpportunitiesSection
                        .fadeSlideIn(delay: 0.25)
                }
                .padding(Spacing.lg)
            }
        }
        .navigationTitle("Storage")
        .task {
            await viewModel.load(modelContext: modelContext)
        }
    }

    // MARK: - Donut Chart

    private var storageBreakdownSection: some View {
        GlassCard {
            VStack(spacing: Spacing.lg) {
                Text("Library Breakdown")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if viewModel.categories.isEmpty {
                    EmptyStateView(icon: "photo.on.rectangle", title: "No Media", message: "Your library is empty.", iconColor: .blue)
                        .frame(height: 200)
                } else {
                    ZStack {
                        Chart(viewModel.categories) { category in
                            SectorMark(
                                angle: .value("Size", category.bytes),
                                innerRadius: .ratio(0.6),
                                angularInset: 2
                            )
                            .foregroundStyle(category.color)
                            .cornerRadius(4)
                        }
                        .frame(height: 200)

                        // Center label
                        VStack(spacing: Spacing.xs) {
                            Text(viewModel.totalLibrarySize.formattedFileSize)
                                .font(.title3.bold())
                            Text("\(viewModel.totalItemCount) items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Legend
                    VStack(spacing: Spacing.sm) {
                        ForEach(viewModel.categories) { category in
                            HStack {
                                Circle()
                                    .fill(category.color)
                                    .frame(width: 10, height: 10)
                                Text(category.name)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(category.count)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(category.bytes.formattedFileSize)
                                    .font(.subheadline.monospacedDigit().bold())
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Device Storage

    private var deviceStorageSection: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                Text("Device Storage")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                GeometryReader { geometry in
                    let usedRatio = viewModel.deviceStorage.totalCapacity > 0
                        ? CGFloat(viewModel.deviceStorage.usedCapacity) / CGFloat(viewModel.deviceStorage.totalCapacity)
                        : 0

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: CornerRadius.small)
                            .fill(Color.cardSurface)
                        RoundedRectangle(cornerRadius: CornerRadius.small)
                            .fill(
                                usedRatio > 0.9
                                    ? LinearGradient(colors: [.red, .red.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                                    : LinearGradient.storageBarGradient
                            )
                            .frame(width: geometry.size.width * usedRatio)
                    }
                }
                .frame(height: 16)

                HStack {
                    Text("\(viewModel.deviceStorage.usedCapacity.formattedFileSize) used")
                        .font(.caption)
                    Spacer()
                    Text("\(viewModel.deviceStorage.availableCapacity.formattedFileSize) available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - iCloud

    private var iCloudSection: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                HStack {
                    Image(systemName: "icloud")
                        .font(.title3)
                        .foregroundStyle(.blue)
                    Text("iCloud Status")
                        .font(.headline)
                    Spacer()
                }

                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Local")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(viewModel.localCount)")
                            .font(.title3.bold())
                        Text("items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Rectangle()
                        .fill(Color.cardBorder)
                        .frame(width: 1, height: 50)

                    Spacer()

                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text("iCloud Only")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(viewModel.iCloudOnlyCount)")
                            .font(.title3.bold())
                        Text(viewModel.iCloudOnlySize.formattedFileSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Trend

    private var trendSection: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                Text("Storage Trend (30 Days)")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if viewModel.snapshots.count < 2 {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("Not enough data yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                } else {
                    Chart(viewModel.snapshots) { snapshot in
                        LineMark(
                            x: .value("Date", snapshot.capturedAt),
                            y: .value("Size", snapshot.totalBytes)
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Date", snapshot.capturedAt),
                            y: .value("Size", snapshot.totalBytes)
                        )
                        .foregroundStyle(.blue.opacity(0.1))
                    }
                    .frame(height: 150)
                    .chartYAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let bytes = value.as(Int64.self) {
                                    Text(bytes.formattedFileSize)
                                        .font(.caption2)
                                }
                            }
                        }
                    }

                    if let first = viewModel.snapshots.first,
                       let last = viewModel.snapshots.last {
                        let delta = last.totalBytes - first.totalBytes
                        HStack {
                            Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .foregroundStyle(delta >= 0 ? .orange : .green)
                            Text(delta >= 0
                                 ? "Added \(delta.formattedFileSize) in 30 days"
                                 : "Freed \(abs(delta).formattedFileSize) in 30 days")
                                .font(.caption)
                                .foregroundStyle(delta >= 0 ? .orange : .green)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cleanup Opportunities

    private var cleanupOpportunitiesSection: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                Text("Cleanup Opportunities")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if viewModel.opportunities.isEmpty {
                    Text("No opportunities found.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.opportunities) { opportunity in
                        Button {
                            appNavigation.showCleanup(tool: opportunity.tool)
                        } label: {
                            HStack(spacing: Spacing.md) {
                                Image(systemName: opportunity.icon)
                                    .foregroundStyle(opportunity.color)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text(opportunity.title)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                    Text(opportunity.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, Spacing.xs)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
