#if os(iOS)
import ActivityKit
import Foundation

struct MicYouActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isMuted: Bool
        var audioLevel: Double
        var updatedAt: Date
    }

    var serverName: String
    var connectedAt: Date
}
#endif
