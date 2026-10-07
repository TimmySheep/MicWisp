import Combine
import Foundation
import ServiceManagement

@MainActor
final class BackendController: ObservableObject {
    @Published var phase: ServicePhase = .stopped
    @Published var connection = SharedConfig.load(ServerPreferences.self, file: "server.json") ?? ServerPreferences()
    @Published var dspSettings = SharedConfig.load(DSPSettings.self, file: "settings.json") ?? DSPSettings()
    @Published var audioDevices: [String] = []
    @Published var adbDevices: [String] = []
    @Published var virtualAudioStatus: [String: Any] = [:]
    @Published var connectedDevice: ConnectedDevice?
    @Published var metrics: AudioMetricsSnapshot?
    @Published var audioLevel: UInt32 = 0
    @Published private(set) var audioPeak: UInt32 = 1
    @Published var spectrum: [Double] = []
    @Published var isMuted = false
    @Published var isMonitoring = false
    @Published var webClientCount = 0
    @Published var aecMessage: String?
    @Published var warningMessage: String?
    @Published var errorMessage: String?
    @Published var diagnosticMessage: String?
    @Published var discoveredServices: [String] = []
    @Published var localAddresses = LocalNetworkAddresses.ipv4()
    @Published private(set) var isBackendReady = false
    @Published private(set) var isLaunchAtLoginEnabled = false

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutBuffer = Data()
    private var pending: [String: CheckedContinuation<Data, Error>] = [:]
    private var terminationWaiter: CheckedContinuation<Void, Never>?
    private var dspSaveTask: Task<Void, Never>?
    private let discovery = ServiceDiscovery()

    init() {
        discovery.start()
        discovery.$services
            .sink { [weak self] services in
                Task { @MainActor [weak self] in self?.discoveredServices = services }
            }
            .store(in: &subscriptions)
        refreshLoginItemState()
    }

    private var subscriptions = Set<AnyCancellable>()

    var canStop: Bool { process?.isRunning == true }
    var phaseLabel: String { phase.label }

    func start() async {
        guard process == nil || process?.isRunning == false else { return }
        errorMessage = nil
        warningMessage = nil
        isBackendReady = false
        phase = .starting

        do {
            try SharedConfig.save(connection, file: "server.json")
            try SharedConfig.save(dspSettings, file: "settings.json")
            guard let executable = SidecarLocator.locate() else {
                throw BackendError.sidecarMissing
            }

            let child = Process()
            child.executableURL = executable
            child.arguments = ["serve", "--jsonl"]
            child.currentDirectoryURL = executable.deletingLastPathComponent()
            let input = Pipe()
            let output = Pipe()
            let diagnostics = Pipe()
            child.standardInput = input
            child.standardOutput = output
            child.standardError = diagnostics
            process = child
            stdinPipe = input
            stdoutPipe = output
            stderrPipe = diagnostics

            output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                Task { @MainActor [weak self] in self?.consumeStdout(data) }
            }
            diagnostics.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                Task { @MainActor [weak self] in self?.diagnosticMessage = text }
            }
            child.terminationHandler = { [weak self] finished in
                let status = finished.terminationStatus
                Task { @MainActor [weak self] in self?.processDidExit(status) }
            }
            try child.run()
        } catch {
            process = nil
            isBackendReady = false
            let message = error.localizedDescription
            errorMessage = message
            phase = .failed(message)
        }
    }

    func stop() async {
        guard let child = process else {
            phase = .stopped
            isBackendReady = false
            return
        }
        if isBackendReady {
            do { _ = try await request("stop") }
            catch { diagnosticMessage = error.localizedDescription }
        } else {
            // Closing stdin is the documented graceful EOF path while startup is in progress.
            try? stdinPipe?.fileHandleForWriting.close()
        }
        if !child.isRunning {
            processDidExit(child.terminationStatus)
            return
        }
        await withCheckedContinuation { continuation in
            terminationWaiter = continuation
            if !child.isRunning {
                terminationWaiter = nil
                continuation.resume()
            }
        }
    }

    func applyConnectionSettings() async {
        do {
            try SharedConfig.save(connection, file: "server.json")
            if isBackendReady {
                _ = try await request("applyConnectionSettings", payload: try jsonObject(connection))
                await stop()
                await start()
            }
            localAddresses = LocalNetworkAddresses.ipv4()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateDSPSettings(_ settings: DSPSettings) {
        dspSettings = settings
        dspSaveTask?.cancel()
        dspSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await self?.applyDSPSettings()
        }
    }

    func applyDSPSettings() async {
        do {
            try SharedConfig.save(dspSettings, file: "settings.json")
            if isBackendReady {
                _ = try await request("applyDspSettings", payload: try jsonObject(dspSettings))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setMuted(_ muted: Bool) async {
        guard isBackendReady else { return }
        do {
            _ = try await request("setMuted", payload: ["isMuted": muted])
            isMuted = muted
        } catch { errorMessage = error.localizedDescription }
    }

    func setMonitoring(_ enabled: Bool) async {
        guard isBackendReady else { return }
        do {
            _ = try await request("setMonitoring", payload: ["enabled": enabled])
            isMonitoring = enabled
        } catch { errorMessage = error.localizedDescription }
    }

    func setSpectrumStreaming(_ enabled: Bool) async {
        guard isBackendReady else { return }
        do { _ = try await request("setSpectrumStreaming", payload: ["enabled": enabled]) }
        catch { diagnosticMessage = error.localizedDescription }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLoginItemState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshLoginItemState() {
        isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    func refreshBackendState() async {
        guard isBackendReady else { return }
        do {
            let dspData = try await request("getDspSettings")
            dspSettings = try JSONDecoder().decode(DSPSettings.self, from: dspData)
            let connectionData = try await request("getConnectionSettings")
            connection = try JSONDecoder().decode(ServerPreferences.self, from: connectionData)
            let audioData = try await request("listAudioDevices")
            if let value = try JSONSerialization.jsonObject(with: audioData) as? [String: Any] {
                audioDevices = value["devices"] as? [String] ?? []
            }
            let adbData = try await request("listAdbDevices")
            if let value = try JSONSerialization.jsonObject(with: adbData) as? [String: Any] {
                let devices = value["devices"] as? [[String: Any]] ?? []
                adbDevices = devices.compactMap { device in
                    guard let serial = device["serial"] as? String else { return nil }
                    let state = device["state"] as? String ?? "unknown"
                    return "\(serial) (\(state))"
                }
            }
            let virtualData = try await request("getVirtualAudioStatus")
            if let value = try JSONSerialization.jsonObject(with: virtualData) as? [String: Any] {
                virtualAudioStatus = value
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func request(_ name: String, payload: Any = [String: Any]()) async throws -> Data {
        guard isBackendReady || name == "stop" else { throw BackendError.notReady }
        guard let stdinPipe else { throw BackendError.pipeClosed }
        let id = UUID().uuidString
        let frame: [String: Any] = ["v": 1, "type": "command", "id": id, "name": name, "payload": payload]
        let data = try JSONSerialization.data(withJSONObject: frame, options: [.sortedKeys, .fragmentsAllowed]) + Data([0x0A])
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            pending[id] = continuation
            do {
                try stdinPipe.fileHandleForWriting.write(contentsOf: data)
            } catch {
                pending.removeValue(forKey: id)?.resume(throwing: error)
            }
        }
    }

    private func consumeStdout(_ data: Data) {
        stdoutBuffer.append(data)
        while let delimiter = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer.prefix(upTo: delimiter)
            stdoutBuffer.removeSubrange(...delimiter)
            guard line.count <= 64 * 1024,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)),
                  let frame = object as? [String: Any] else {
                failProtocol("Malformed or oversized JSONL frame")
                return
            }
            handle(frame)
        }
        if stdoutBuffer.count > 64 * 1024 { failProtocol("JSONL frame exceeded 64 KiB") }
    }

    private func handle(_ frame: [String: Any]) {
        guard frame["v"] as? Int == 1, let type = frame["type"] as? String else {
            failProtocol("Unsupported backend protocol frame")
            return
        }
        switch type {
        case "ready":
            isBackendReady = true
            phase = .running
            Task { await refreshBackendState() }
        case "error":
            let message = (frame["error"] as? [String: Any])?["message"] as? String ?? "Backend startup failed"
            errorMessage = message
            phase = .failed(message)
        case "response":
            guard let id = frame["id"] as? String, let continuation = pending.removeValue(forKey: id) else { return }
            if frame["ok"] as? Bool == true {
                do {
                    let payload = frame["payload"] ?? [String: Any]()
                    let data = try JSONSerialization.data(withJSONObject: payload, options: [.fragmentsAllowed])
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            } else {
                let message = (frame["error"] as? [String: Any])?["message"] as? String ?? "Backend command failed"
                continuation.resume(throwing: BackendError.command(message))
            }
        case "event":
            guard let name = frame["name"] as? String,
                  let payload = frame["payload"] as? [String: Any] else { return }
            handleEvent(name, payload: payload)
        default:
            failProtocol("Unknown backend frame type: \(type)")
        }
    }

    private func handleEvent(_ name: String, payload: [String: Any]) {
        switch name {
        case "device_connected":
            connectedDevice = ConnectedDevice(
                name: payload["name"] as? String ?? L10n.string("value.unknown"),
                ip: payload["ip"] as? String ?? "",
                latency: (payload["latency"] as? NSNumber)?.uint32Value ?? 0
            )
        case "device_disconnected": connectedDevice = nil
        case "audio_metrics":
            metrics = AudioMetricsSnapshot(
                bitrate: int(payload, "bitrate"),
                sampleRate: int(payload, "sampleRate"),
                latencyMs: int64(payload, "latencyMs"),
                networkLatencyMs: int64(payload, "networkLatencyMs"),
                packetLossRate: double(payload, "packetLossRate"),
                jitterMs: double(payload, "jitterMs"),
                bufferDurationMs: int64(payload, "bufferDurationMs")
            )
        case "audio_level":
            audioLevel = (payload["level"] as? NSNumber)?.uint32Value ?? 0
            audioPeak = max(audioPeak, audioLevel)
        case "audio_spectrum":
            spectrum = (payload["processed"] as? [NSNumber])?.map(\.doubleValue) ?? []
        case "mute_state_changed": isMuted = payload["isMuted"] as? Bool ?? isMuted
        case "monitoring_state_changed": isMonitoring = payload["enabled"] as? Bool ?? isMonitoring
        case "web_client_count": webClientCount = int(payload, "count")
        case "udp_audio_warning": warningMessage = L10n.string("warning.udp")
        case "aec_status_changed":
            let available = payload["available"] as? Bool ?? false
            let enabled = payload["enabled"] as? Bool ?? false
            aecMessage = available && enabled ? nil : (payload["reason"] as? String)
        case "install_progress": diagnosticMessage = payload["message"] as? String
        case "server_stopped":
            isBackendReady = false
            connectedDevice = nil
            metrics = nil
            audioLevel = 0
            spectrum = []
            webClientCount = 0
            isMuted = false
            isMonitoring = false
        default: break
        }
    }

    private func processDidExit(_ status: Int32) {
        guard process != nil else { return }
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        isBackendReady = false
        connectedDevice = nil
        metrics = nil
        audioLevel = 0
        spectrum = []
        webClientCount = 0
        isMuted = false
        isMonitoring = false
        for (_, continuation) in pending { continuation.resume(throwing: BackendError.pipeClosed) }
        pending.removeAll()
        if status == 0 {
            phase = .stopped
        } else if case .failed = phase {
            // Keep the structured startup/command error already shown to the user.
        } else {
            let message = "Backend exited with status \(status)"
            phase = .failed(message)
            errorMessage = message
        }
        terminationWaiter?.resume()
        terminationWaiter = nil
    }

    private func failProtocol(_ message: String) {
        isBackendReady = false
        errorMessage = message
        phase = .failed(message)
        try? stdinPipe?.fileHandleForWriting.close()
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: [.fragmentsAllowed])
    }

    private func decode<T: Decodable>(_ type: T.Type, from object: [String: Any]) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }

    private func int(_ object: [String: Any], _ key: String) -> Int {
        (object[key] as? NSNumber)?.intValue ?? 0
    }

    private func int64(_ object: [String: Any], _ key: String) -> Int64 {
        (object[key] as? NSNumber)?.int64Value ?? 0
    }

    private func double(_ object: [String: Any], _ key: String) -> Double {
        (object[key] as? NSNumber)?.doubleValue ?? 0
    }
}

private enum BackendError: LocalizedError {
    case sidecarMissing
    case notReady
    case pipeClosed
    case command(String)

    var errorDescription: String? {
        switch self {
        case .sidecarMissing: L10n.string("settings.backendMissing")
        case .notReady: "Backend is not ready"
        case .pipeClosed: "Backend control pipe is closed"
        case let .command(message): message
        }
    }
}
