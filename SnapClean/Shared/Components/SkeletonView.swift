import SwiftUI

struct SkeletonView: View {
    var cornerRadius: CGFloat = CornerRadius.small
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.cardSurface)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.cardBorder, lineWidth: 0.5)
            }
            .overlay {
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.08),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.6)
                    .offset(x: phase * geometry.size.width)
                }
                .clipped()
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: Spacing.md) {
            SkeletonView(cornerRadius: CornerRadius.small)
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                SkeletonView()
                    .frame(width: 120, height: 14)
                SkeletonView()
                    .frame(width: 80, height: 12)
            }

            Spacer()
        }
    }
}

struct SkeletonGrid: View {
    let columns: Int
    let rows: Int

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: columns),
            spacing: Spacing.sm
        ) {
            ForEach(0..<(columns * rows), id: \.self) { _ in
                SkeletonView(cornerRadius: CornerRadius.small)
                    .aspectRatio(1, contentMode: .fill)
            }
        }
    }
}

struct SkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SkeletonView(cornerRadius: CornerRadius.medium)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                SkeletonView()
                    .frame(width: 100, height: 14)
                SkeletonView()
                    .frame(width: 140, height: 12)
            }
        }
        .glassCard()
    }
}
