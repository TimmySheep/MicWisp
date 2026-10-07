import Foundation
import Combine
import Network

@MainActor
final class ServiceDiscovery: ObservableObject {
    @Published private(set) var services: [String] = []
    private var browsers: [NWBrowser] = []

    func start() {
        guard browsers.isEmpty else { return }
        for type in ["_micyou._tcp", "_micyou-web._tcp"] {
            let browser = NWBrowser(for: .bonjour(type: type, domain: "local."), using: NWParameters())
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                let names = results.compactMap { result -> String? in
                    guard case let .service(name, serviceType, domain, _) = result.endpoint else { return nil }
                    return "\(name) · \(serviceType) · \(domain)"
                }
                Task { @MainActor [weak self] in
                    self?.services = Array(Set(names)).sorted()
                }
            }
            browser.stateUpdateHandler = { [weak self] state in
                if case let .failed(error) = state {
                    Task { @MainActor [weak self] in
                        self?.services = ["mDNS unavailable: \(error.localizedDescription)"]
                    }
                }
            }
            browser.start(queue: .main)
            browsers.append(browser)
        }
    }

    func stop() {
        browsers.forEach { $0.cancel() }
        browsers.removeAll()
        services.removeAll()
    }
}
