#if os(iOS)
import ActivityKit
import Foundation
import UIKit

@MainActor
final class MicYouActivityCoordinator {
    private var activity: Activity<MicYouActivityAttributes>?
    private var updateTask: Task<Void, Never>?
    private var pendingMute = false
    private var pendingLevel = 0.0

    func start(serverName: String) {
        guard UIDevice.current.userInterfaceIdiom == .phone,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        Task {
            end()
            let attributes = MicYouActivityAttributes(serverName: serverName, connectedAt: Date())
            let state = MicYouActivityAttributes.ContentState(isMuted: false, audioLevel: 0, updatedAt: Date())
            do {
                activity = try Activity.request(attributes: attributes, contentState: state, pushType: nil)
            } catch {
                MicYouLogger.shared.write("Live Activity could not start: \(error.localizedDescription)")
            }
        }
    }

    func update(isMuted: Bool, level: Float) {
        pendingMute = isMuted
        pendingLevel = Double(level)
        guard updateTask == nil else { return }
        updateTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self else { return }
            if let activity = self.activity {
                let state = MicYouActivityAttributes.ContentState(isMuted: self.pendingMute, audioLevel: self.pendingLevel, updatedAt: Date())
                await activity.update(using: state)
            }
            self.updateTask = nil
        }
    }

    func end() {
        updateTask?.cancel()
        updateTask = nil
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(using: nil, dismissalPolicy: .immediate) }
    }
}
#endif
