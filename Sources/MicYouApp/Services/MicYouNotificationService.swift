import Foundation
import UserNotifications

final class MicYouNotificationService {
    static let shared = MicYouNotificationService()
    private let identifier = "micyou-streaming"

    func showStreaming(label: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "\(ProductBrand.name) is streaming"
            content.body = "Microphone audio is being sent to \(label)."
            content.sound = nil
            let request = UNNotificationRequest(identifier: self.identifier, content: content, trigger: nil)
            center.add(request) { error in
                if let error { MicYouLogger.shared.write("Streaming notification failed: \(error.localizedDescription)") }
            }
        }
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func clearStreamingNotice() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
