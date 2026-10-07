import Foundation
import Network

struct DiscoveredServer: Identifiable {
    let id: String
    let name: String
    let endpoint: NWEndpoint
}

final class MicYouServiceDiscovery {
    var onResults: (([DiscoveredServer]) -> Void)?
    var onState: ((Bool) -> Void)?
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_micyou._tcp", domain: "local."), using: parameters)
        self.browser = browser
        browser.stateUpdateHandler = { [weak self] state in
            let scanning: Bool
            switch state {
            case .ready: scanning = true
            case .failed, .cancelled: scanning = false
            default: return
            }
            DispatchQueue.main.async { self?.onState?(scanning) }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let servers = results.compactMap { result -> DiscoveredServer? in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                return DiscoveredServer(id: String(describing: result.endpoint), name: name, endpoint: result.endpoint)
            }
            DispatchQueue.main.async { self?.onResults?(servers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) }
        }
        browser.start(queue: .main)
    }

    func restart() {
        stop()
        start()
    }

    func stop() {
        browser?.cancel()
        browser = nil
        DispatchQueue.main.async { self.onState?(false) }
    }
}
