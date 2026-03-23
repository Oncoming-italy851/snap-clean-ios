import Foundation
import Observation

@MainActor
@Observable
final class AppNavigation {
    var selectedTab: AppTab = .swipe
    var cleanupPath: [CleanupTool] = []
    private(set) var swipeDismissRequestID = UUID()

    func showCleanup(tool: CleanupTool? = nil) {
        if let tool {
            cleanupPath = [tool]
        } else {
            cleanupPath.removeAll()
        }
        selectedTab = .cleanup
        requestSwipeDismissal()
    }

    func showCleanupHome() {
        cleanupPath.removeAll()
        selectedTab = .cleanup
        requestSwipeDismissal()
    }

    func returnToSwipeHome() {
        cleanupPath.removeAll()
        selectedTab = .swipe
        requestSwipeDismissal()
    }

    private func requestSwipeDismissal() {
        swipeDismissRequestID = UUID()
    }
}
