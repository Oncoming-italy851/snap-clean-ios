import SwiftUI

// MARK: - Fade Slide In

struct FadeSlideInModifier: ViewModifier {
    let delay: Double
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 20)
            .onAppear {
                if reduceMotion {
                    isVisible = true
                } else {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(delay)) {
                        isVisible = true
                    }
                }
            }
    }
}

extension View {
    func fadeSlideIn(delay: Double = 0) -> some View {
        modifier(FadeSlideInModifier(delay: delay))
    }
}

// MARK: - Scale On Press Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension View {
    func scaleOnPress() -> some View {
        self.buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - State Transition

extension AnyTransition {
    static var stateTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.95)).animation(.spring(response: 0.35, dampingFraction: 0.85))
    }
}

// MARK: - Animated Counter

struct AnimatedNumberModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.contentTransition(.numericText())
    }
}

extension View {
    func animatedNumber() -> some View {
        modifier(AnimatedNumberModifier())
    }
}
