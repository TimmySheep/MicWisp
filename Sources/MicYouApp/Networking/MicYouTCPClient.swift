import Foundation
import Network

final class MicYouTCPClient {
    private let queue = DispatchQueue(label: "com.timmy.micyou.tcp")
    private var connection: NWConnection?
    private var frameDecoder = MicYouFrameDecoder()
    private var handshakeBuffer = Data()
    private var completion: ((Result<Void, Error>) -> Void)?
    private var sequenceNumber: Int32 = 0
    private var muted = false
    private var didFinish = false
    private var timeoutWorkItem: DispatchWorkItem?
    private var audioSendInProgress = false
    private var newestPendingAudio: PendingAudio?

    var onMessage: ((MicYouMessage) -> Void)?
    var onDisconnect: ((Error?) -> Void)?

    func connect(to endpoint: NWEndpoint, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, self.connection == nil else { return }
            self.completion = completion
            self.didFinish = false
            self.frameDecoder = MicYouFrameDecoder()
            self.handshakeBuffer.removeAll(keepingCapacity: true)
            let connection = NWConnection(to: endpoint, using: .tcp)
            self.connection = connection
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.sendHandshake()
                case .failed(let error):
                    self.fail(error)
                case .cancelled:
                    self.finish(error: nil)
                default:
                    break
                }
            }
            connection.start(queue: self.queue)
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.completion != nil else { return }
                self.fail(MicYouClientError.connectionTimedOut)
            }
            self.timeoutWorkItem = timeout
            self.queue.asyncAfter(deadline: .now() + 12, execute: timeout)
        }
    }

    func send(_ message: MicYouMessage) {
        queue.async { self.sendOnQueue(message) }
    }

    func setMuted(_ muted: Bool, sendControl: Bool = true) {
        queue.async {
            self.muted = muted
            if muted { self.newestPendingAudio = nil }
            if sendControl { self.sendOnQueue(.mute(isMuted: muted)) }
        }
    }

    func sendAudio(_ bytes: Data, sampleRate: Int32, channelCount: Int32) {
        queue.async {
            guard !self.muted, self.connection != nil else { return }
            let audio = PendingAudio(bytes: bytes, sampleRate: sampleRate, channelCount: channelCount)
            if self.audioSendInProgress {
                self.newestPendingAudio = audio
            } else {
                self.sendNextAudio(audio)
            }
        }
    }

    func cancel() {
        queue.async {
            self.completion = nil
            self.didFinish = true
            self.timeoutWorkItem?.cancel()
            self.timeoutWorkItem = nil
            self.newestPendingAudio = nil
            self.connection?.stateUpdateHandler = nil
            self.connection?.cancel()
            self.connection = nil
        }
    }

    private func sendHandshake() {
        guard let connection else { return }
        connection.send(content: Data("MicYouCheck1".utf8), completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if let error { self.fail(error); return }
            self.receiveHandshake()
        })
    }

    private func receiveHandshake() {
        guard let connection else { return }
        let expected = Data("MicYouCheck2".utf8)
        connection.receive(minimumIncompleteLength: 1, maximumLength: expected.count - handshakeBuffer.count) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error { self.fail(error); return }
            if let data { self.handshakeBuffer.append(data) }
            if self.handshakeBuffer.count == expected.count {
                guard self.handshakeBuffer == expected else {
                    self.fail(MicYouClientError.handshakeRejected)
                    return
                }
                self.sendOnQueue(.connect(sessionID: 0)) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success:
                        self.timeoutWorkItem?.cancel()
                        self.timeoutWorkItem = nil
                        let callback = self.completion
                        self.completion = nil
                        callback?(.success(()))
                        self.receiveNextFrame()
                    case .failure(let error): self.fail(error)
                    }
                }
            } else if isComplete {
                self.fail(MicYouClientError.handshakeRejected)
            } else {
                self.receiveHandshake()
            }
        }
    }

    private func receiveNextFrame() {
        guard let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error { self.fail(error); return }
            do {
                if let data {
                    for payload in try self.frameDecoder.append(data) {
                        let message = try MicYouProtobufCodec.decode(payload)
                        if case .ping(let timestamp) = message {
                            self.sendOnQueue(.pong(timestamp: timestamp))
                        }
                        DispatchQueue.main.async { self.onMessage?(message) }
                    }
                }
            } catch {
                self.fail(error)
                return
            }
            if isComplete {
                self.finish(error: nil)
            } else {
                self.receiveNextFrame()
            }
        }
    }

    private func sendOnQueue(_ message: MicYouMessage, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard let connection else {
            completion?(.failure(MicYouClientError.notConnected))
            return
        }
        do {
            let frame = try MicYouFrameDecoder.encode(payload: MicYouProtobufCodec.encode(message))
            connection.send(content: frame, completion: .contentProcessed { error in
                if let error {
                    completion?(.failure(error))
                    self.fail(error)
                } else {
                    completion?(.success(()))
                }
            })
        } catch {
            completion?(.failure(error))
            fail(error)
        }
    }

    private func sendNextAudio(_ audio: PendingAudio) {
        guard !muted, connection != nil else { return }
        let packet = MicYouOrderedAudioPacket(
            sequenceNumber: sequenceNumber,
            audioPacket: MicYouAudioPacket(buffer: audio.bytes, sampleRate: audio.sampleRate, channelCount: audio.channelCount, audioFormat: 1, codec: MicYouCodec.pcm.rawValue),
            timestamp: Int64(Date().timeIntervalSince1970 * 1_000),
            sessionID: 0
        )
        sequenceNumber &+= 1
        audioSendInProgress = true
        sendOnQueue(.audio(packet)) { [weak self] _ in
            guard let self else { return }
            self.audioSendInProgress = false
            guard let next = self.newestPendingAudio else { return }
            self.newestPendingAudio = nil
            self.sendNextAudio(next)
        }
    }

    private func fail(_ error: Error) {
        guard !didFinish else { return }
        didFinish = true
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        newestPendingAudio = nil
        let callback = completion
        completion = nil
        callback?(.failure(error))
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        DispatchQueue.main.async { self.onDisconnect?(error) }
    }

    private func finish(error: Error?) {
        guard !didFinish else { return }
        if completion != nil {
            fail(error ?? MicYouClientError.handshakeRejected)
            return
        }
        didFinish = true
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        newestPendingAudio = nil
        connection = nil
        DispatchQueue.main.async { self.onDisconnect?(error) }
    }
}

private struct PendingAudio {
    let bytes: Data
    let sampleRate: Int32
    let channelCount: Int32
}

enum MicYouClientError: LocalizedError {
    case handshakeRejected
    case notConnected
    case connectionTimedOut

    var errorDescription: String? {
        switch self {
        case .handshakeRejected: "The server did not complete the MicYou handshake."
        case .notConnected: "The server connection is not ready."
        case .connectionTimedOut: "The server did not respond within 12 seconds."
        }
    }
}
