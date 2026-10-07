import AVFoundation
import Foundation

final class MicYouMicrophone {
    let sampleRate: Int
    let channelCount: Int
    private let useSystemVoiceProcessing: Bool
    var onAudio: ((Data, Float) -> Void)?

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?
    private var interruptionObserver: NSObjectProtocol?

    init(sampleRate: Int, channelCount: Int, useSystemVoiceProcessing: Bool) throws {
        guard [16_000, 44_100, 48_000, 96_000].contains(sampleRate), [1, 2].contains(channelCount) else {
            throw MicYouMicrophoneError.unsupportedFormat
        }
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.useSystemVoiceProcessing = useSystemVoiceProcessing
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: useSystemVoiceProcessing ? .voiceChat : .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setPreferredSampleRate(Double(sampleRate))
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(channelCount),
            interleaved: true
        ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw MicYouMicrophoneError.converterUnavailable
        }
        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak self] buffer, _ in
            self?.convertAndSend(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            do { try self?.engine.start() } catch { MicYouLogger.shared.write("Audio session could not resume: \(error.localizedDescription)") }
        }
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func convertAndSend(_ input: AVAudioPCMBuffer) {
        guard let converter, let outputFormat else { return }
        let ratio = outputFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * ratio) + 32)
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
        var didSupplyInput = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if didSupplyInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            didSupplyInput = true
            inputStatus.pointee = .haveData
            return input
        }
        if let conversionError {
            MicYouLogger.shared.write("Audio conversion failed: \(conversionError.localizedDescription)")
            return
        }
        guard status != .error, output.frameLength > 0,
              let raw = output.audioBufferList.pointee.mBuffers.mData else { return }

        let byteCount = Int(output.audioBufferList.pointee.mBuffers.mDataByteSize)
        let bytes = Data(bytes: raw, count: byteCount)
        let rms = measureLevel(input)
        onAudio?(bytes, rms)
    }

    private func measureLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum = 0.0
        for frame in 0..<count {
            let sample = Double(channels[0][frame])
            sum += sample * sample
        }
        let rms = sqrt(sum / Double(count))
        return Float(min(1, max(0, rms * 3.5)))
    }
}

enum MicYouMicrophoneError: LocalizedError {
    case unsupportedFormat
    case converterUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "The selected audio format is not supported."
        case .converterUnavailable: "This device could not create the selected audio converter."
        }
    }
}
