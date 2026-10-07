import Foundation
import WidgetKit

/// Single source of truth for the independent client's user-facing product name.
enum ProductBrand {
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Client"
    }
    static var urlScheme: String {
        Bundle.main.object(forInfoDictionaryKey: "MICWISP_URL_SCHEME") as? String ?? "micwisp"
    }
    static let protocolDescription = "MicYou-compatible independent client"
    static let statusWidgetKind = "MicWispStatusWidget"

    static var appGroup: String {
        Bundle.main.object(forInfoDictionaryKey: "MICWISP_APP_GROUP") as? String ?? ""
    }

    static func updateWidgetStatus(streaming: Bool, server: String, muted: Bool) {
        guard !appGroup.isEmpty, let defaults = UserDefaults(suiteName: appGroup) else { return }
        defaults.set(streaming, forKey: "streaming")
        defaults.set(server, forKey: "server")
        defaults.set(muted, forKey: "muted")
        WidgetCenter.shared.reloadTimelines(ofKind: statusWidgetKind)
    }
}
