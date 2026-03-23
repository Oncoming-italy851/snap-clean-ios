import SwiftUI

struct SwipeSessionView: View {
    @Bindable var viewModel: SwipeSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(AppNavigation.self) private var appNavigation

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var swipeTask: Task<Void, Never>?

    private let hapticLight = UIImpactFeedbackGenerator(style: .light)
    private let hapticHeavy = UIImpactFeedbackGenerator(style: .heavy)

    var body: some View {
        let isBootstrapping = !viewModel.hasLoadedInitialAssets || viewModel.isLoading

        VStack(spacing: 0) {
            // Progress bar
            progressBar

            if isBootstrapping {
                Spacer()
                ProgressView("Loading photos...")
                Spacer()
            } else if viewModel.visibleCards.isEmpty {
                Spacer()
                emptyState
                Spacer()
            } else {
                // Card stack
                cardStack
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                // Action buttons
                actionBar
                    .padding(.top, 12)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle("Swipe Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task { await viewModel.endSession() }
                } label: {
                    Text("End")
                        .foregroundStyle(.red)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.undo() }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(viewModel.undoStack.isEmpty)
            }
        }
        .sheet(isPresented: $viewModel.showAlbumPicker) {
            AlbumPickerSheet(
                photoService: viewModel.photoService,
                onAlbumSelected: { albumId in
                    await viewModel.addToAlbum(albumId: albumId)
                },
                onSkip: {
                    viewModel.skipKeep()
                }
            )
            .presentationDetents([.medium, .large])
        }
        .navigationDestination(isPresented: $viewModel.showCompletion) {
            SessionCompletionView(viewModel: viewModel)
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task {
            await viewModel.loadAssetsIfNeeded()
        }
        .onChange(of: appNavigation.swipeDismissRequestID) { _, _ in
            dismiss()
        }
        .onDisappear {
            swipeTask?.cancel()
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geometry in
            let progress = viewModel.assets.isEmpty ? 0 : CGFloat(viewModel.currentIndex) / CGFloat(viewModel.assets.count)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(.systemGray5))
                Rectangle()
                    .fill(.blue)
                    .frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: 3)
    }

    // MARK: - Card Stack

    private var cardStack: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(Array(viewModel.visibleCards.enumerated().reversed()), id: \.element.id) { index, asset in
                    let isTop = index == 0
                    let scale = 1.0 - CGFloat(index) * 0.05
                    let yOffset = CGFloat(index) * 10

                    CardView(
                        asset: asset,
                        photoService: viewModel.photoService,
                        isTopCard: isTop,
                        dragOffset: isTop ? dragOffset : .zero
                    )
                    .scaleEffect(isTop ? 1.0 : scale)
                    .offset(y: isTop ? 0 : yOffset)
                    .offset(x: isTop ? dragOffset.width : 0, y: isTop ? dragOffset.height : 0)
                    .rotationEffect(isTop ? .degrees(Double(dragOffset.width / 20)) : .zero)
                    .gesture(isTop && !viewModel.isPerformingMutation ? dragGesture : nil)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dragOffset)
                    .allowsHitTesting(isTop && !viewModel.isPerformingMutation)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    hapticLight.impactOccurred()
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                isDragging = false
                let threshold: CGFloat = UIScreen.main.bounds.width * 0.4
                let velocityThreshold: CGFloat = 500
                let predictedWidth = value.predictedEndTranslation.width

                if value.translation.width > threshold || predictedWidth > velocityThreshold {
                    // Swipe right — keep
                    hapticHeavy.impactOccurred()
                    performSwipeAnimation(offset: CGSize(width: 1000, height: value.translation.height)) {
                        viewModel.swipeRight()
                    }
                } else if value.translation.width < -threshold || predictedWidth < -velocityThreshold {
                    // Swipe left — delete
                    hapticHeavy.impactOccurred()
                    performSwipeAnimation(offset: CGSize(width: -1000, height: value.translation.height)) {
                        viewModel.swipeLeft()
                    }
                } else {
                    // Snap back
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 32) {
            // Delete button
            Button {
                hapticHeavy.impactOccurred()
                performSwipeAnimation(offset: CGSize(width: -1000, height: 0)) {
                    viewModel.swipeLeft()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(.red)
                    .clipShape(Circle())
                    .shadow(color: .red.opacity(0.3), radius: 8)
            }

            // Info / Skip button
            Button {
                viewModel.skip()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color(.systemGray))
                    .clipShape(Circle())
            }

            // Keep / Add to Album button
            Button {
                hapticHeavy.impactOccurred()
                performSwipeAnimation(offset: CGSize(width: 1000, height: 0)) {
                    viewModel.swipeRight()
                }
            } label: {
                Image(systemName: "checkmark")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(.green)
                    .clipShape(Circle())
                    .shadow(color: .green.opacity(0.3), radius: 8)
            }
        }
        .disabled(!viewModel.hasMoreCards || viewModel.isPerformingMutation)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: viewModel.allPhotosAlreadySwiped ? "checkmark.seal" : "checkmark.circle")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            if viewModel.allPhotosAlreadySwiped {
                Text("All Photos Reviewed!")
                    .font(.title2.bold())
                Text("You've already swiped through all your photos. Try \"All Media\" to review again, or reset swipe history in Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxl)

                Button {
                    dismiss()
                } label: {
                    Text("Try Another Filter")
                        .font(.headline)
                        .padding(.horizontal, Spacing.xxxl)
                        .padding(.vertical, Spacing.md)
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                }
                .scaleOnPress()
            } else {
                Text("All Caught Up!")
                    .font(.title2.bold())
                Text("No more photos to review with this filter.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }

    private func performSwipeAnimation(
        offset: CGSize,
        action: @escaping @MainActor () async -> Void
    ) {
        guard !viewModel.isPerformingMutation else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            dragOffset = offset
        }

        swipeTask?.cancel()
        swipeTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                dragOffset = .zero
            }
            await action()
        }
    }
}
