import AVFoundation
import Combine
import Network
import SwiftUI
import UIKit

@MainActor
final class MicYouAppModel: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting
        case streaming
        case failed(String)

        var title: String {
            switch self {
            case .idle: "Not connected"
            case .connecting: "Connecting…"
            case .streaming: "Streaming"
            case .failed(let message): message
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var audioLevel = 0.0
    @Published private(set) var isMuted = false
    @Published private(set) var discoveredServers: [DiscoveredServer] = []
    @Published private(set) var isScanning = false
    @Published private(set) var selectedServerName: String?

    let settings = MicYouSettings()
    private let discovery = MicYouServiceDiscovery()
    private let activity = MicYouActivityCoordinator()
    private let logger = MicYouLogger.shared
    private var connection: MicYouTCPClient?
    private var microphone: MicYouMicrophone?
    private var reconnectAttempt = 0
    private var reconnectWorkItem: DispatchWorkItem?
    private var activeEndpoint: NWEndpoint?
    private var activeServerLabel = ""
    private var connectionGeneration = UUID()

    init() {
        discovery.onResults = { [weak self] servers in
            Task { @MainActor in self?.discoveredServers = servers }
        }
        discovery.onState = { [weak self] scanning in
            Task { @MainActor in self?.isScanning = scanning }
        }
    }

    func startDiscovery() { discovery.start() }
    func refreshDiscovery() { discovery.restart() }

    func connect(to server: DiscoveredServer) {
        selectedServerName = server.name
        connect(endpoint: server.endpoint, label: server.name)
    }

    func connectManually() {
        let host = settings.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, (1...65_535).contains(settings.port) else {
            state = .failed("Enter a valid host and port")
            return
        }
        settings.rememberRecentHost(host)
        selectedServerName = host
        connect(endpoint: .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(settings.port))!), label: host)
    }

    private func connect(endpoint: NWEndpoint, label: String) {
        disconnect(userInitiated: false)
        activeEndpoint = endpoint
        activeServerLabel = label
        reconnectAttempt = 0
        beginConnectionAttempt(to: endpoint, label: label)
    }

    private func beginConnectionAttempt(to endpoint: NWEndpoint, label: String) {
        reconnectWorkItem = nil
        state = .connecting
        logger.write("Connecting to \(label)")
        let generation = UUID()
        connectionGeneration = generation

        requestMicrophonePermission { [weak self] granted in
            guard let self, self.connectionGeneration == generation else { return }
            guard granted else {
                self.state = .failed("Microphone access is required")
                self.activeEndpoint = nil
                self.logger.write("Microphone permission denied")
                return
            }
            let client = MicYouTCPClient()
            client.onMessage = { [weak self] message in
                Task { @MainActor in
                    guard let self, self.connectionGeneration == generation else { return }
                    self.received(message)
                }
            }
            client.onDisconnect = { [weak self] error in
                Task { @MainActor in
                    guard let self, self.connectionGeneration == generation else { return }
                    self.connectionEnded(error)
                }
            }
            self.connection = client
            client.connect(to: endpoint) { [weak self, weak client] result in
                Task { @MainActor in
                    guard let self, let client, self.connectionGeneration == generation else { return }
                    switch result {
                    case .success:
                        self.reconnectAttempt = 0
                        self.logger.write("Handshake complete with \(label)")
                        guard self.startMicrophone(using: client) else { return }
                        self.state = .streaming
                        ProductBrand.updateWidgetStatus(streaming: true, server: label, muted: self.isMuted)
                        self.activity.start(serverName: label)
                        self.updateIdleTimer()
                        if self.settings.streamingNotification { MicYouNotificationService.shared.showStreaming(label: label) }
                    case .failure(let error):
                        self.connectionEnded(error)
                    }
                }
            }
        }
    }

    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: completion(true)
        case .denied: completion(false)
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                DispatchQueue.main.async { completion(allowed) }
            }
        @unknown default: completion(false)
        }
    }

    @discardableResult
    private func startMicrophone(using client: MicYouTCPClient) -> Bool {
        do {
            let capture = try MicYouMicrophone(
                sampleRate: settings.sampleRate,
                channelCount: settings.channelCount,
                useSystemVoiceProcessing: settings.noiseSuppression == .system
            )
            let outputSampleRate = capture.sampleRate
            let outputChannelCount = capture.channelCount
            capture.onAudio = { [weak self, weak client] bytes, level in
                client?.sendAudio(bytes, sampleRate: Int32(outputSampleRate), channelCount: Int32(outputChannelCount))
                Task { @MainActor in
                    guard let self else { return }
                    self.audioLevel = Double(level)
                    self.activity.update(isMuted: self.isMuted, level: level)
                }
            }
            try capture.start()
            microphone = capture
            return true
        } catch {
            logger.write("Audio capture failed: \(error.localizedDescription)")
            state = .failed("Microphone error: \(error.localizedDescription)")
            activeEndpoint = nil
            connection = nil
            ProductBrand.updateWidgetStatus(streaming: false, server: selectedServerName ?? "", muted: false)
            client.cancel()
            updateIdleTimer()
            return false
        }
    }

    func toggleMute() {
        guard state == .streaming else { return }
        isMuted.toggle()
        connection?.setMuted(isMuted)
        ProductBrand.updateWidgetStatus(streaming: true, server: selectedServerName ?? "", muted: isMuted)
        activity.update(isMuted: isMuted, level: Float(audioLevel))
        logger.write(isMuted ? "Microphone muted" : "Microphone unmuted")
    }

    func disconnect(userInitiated: Bool = true) {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        microphone?.stop()
        microphone = nil
        connection?.cancel()
        connection = nil
        connectionGeneration = UUID()
        if userInitiated { activeEndpoint = nil }
        MicYouNotificationService.shared.clearStreamingNotice()
        activity.end()
        ProductBrand.updateWidgetStatus(streaming: false, server: selectedServerName ?? "", muted: false)
        isMuted = false
        audioLevel = 0
        if userInitiated { state = .idle }
        updateIdleTimer()
    }

    private func received(_ message: MicYouMessage) {
        switch message {
        case .ping:
            break // MicYouTCPClient responds immediately on its serial network queue.
        case .mute(let muted):
            if let muted {
                isMuted = muted
                connection?.setMuted(muted, sendControl: false)
                ProductBrand.updateWidgetStatus(streaming: true, server: selectedServerName ?? "", muted: muted)
                activity.update(isMuted: muted, level: Float(audioLevel))
            }
        case .plugin(let plugin):
            logger.write("Plugin message \(plugin.source) → \(plugin.target), topic=\(plugin.topic)")
        case .connect, .pong, .audio:
            break
        }
    }

    private func connectionEnded(_ error: Error?) {
        guard state == .streaming || state == .connecting else { return }
        connectionGeneration = UUID()
        microphone?.stop()
        microphone = nil
        connection = nil
        MicYouNotificationService.shared.clearStreamingNotice()
        activity.end()
        ProductBrand.updateWidgetStatus(streaming: false, server: selectedServerName ?? "", muted: false)
        updateIdleTimer()
        if let error {
            logger.write("Connection ended: \(error.localizedDescription)")
            scheduleReconnect(after: error)
        } else {
            state = .idle
            logger.write("Connection ended")
        }
    }

    private func scheduleReconnect(after error: Error) {
        guard let endpoint = activeEndpoint else {
            state = .failed("Disconnected: \(error.localizedDescription)")
            return
        }
        guard reconnectAttempt < 5 else {
            activeEndpoint = nil
            state = .failed("Reconnect attempts exhausted: \(error.localizedDescription)")
            logger.write("Automatic reconnect stopped after 5 attempts")
            return
        }
        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt - 1)), 30)
        state = .connecting
        logger.write("Reconnect attempt \(reconnectAttempt) scheduled in \(Int(delay))s")
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.activeEndpoint != nil else { return }
            self.beginConnectionAttempt(to: endpoint, label: self.activeServerLabel)
        }
        reconnectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        if phase == .active { updateIdleTimer() }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = settings.keepScreenAwake && state == .streaming
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == ProductBrand.urlScheme else { return }
        switch url.host {
        case "mute": if !isMuted { toggleMute() }
        case "unmute": if isMuted { toggleMute() }
        case "disconnect": disconnect()
        default: break
        }
    }
}
