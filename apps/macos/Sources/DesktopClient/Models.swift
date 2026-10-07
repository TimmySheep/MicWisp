import Foundation

enum ServicePhase: Equatable {
    case stopped
    case starting
    case running
    case failed(String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .stopped: L10n.string("status.stopped")
        case .starting: L10n.string("status.starting")
        case .running: L10n.string("status.running")
        case .failed: L10n.string("status.failed")
        }
    }
}

struct ServerPreferences: Codable, Equatable {
    var port: UInt16 = 8554
    var webPort: UInt16 = 8443
    var mode = "wifi"
    var bindAddress = "0.0.0.0"
    var autoBind = true
    var outputDevice = ""
    var muteSync = true
}

struct EqualizerSettings: Codable, Equatable {
    var enabled = false
    var preAmp: Float = 0
    var gains = Array(repeating: Float.zero, count: 10)
}

struct DSPSettings: Codable, Equatable {
    var gain: Float = 0
    var nsEnabled = false
    var nsType = "PureVox"
    var nsIntensity: Float = 50
    var dereverbEnabled = false
    var dereverbLevel: Float = 50
    var agcEnabled = false
    var agcTarget: Float = 16_000
    var agcAttack: Float = 50
    var agcDecay: Float = 50
    var vadEnabled = false
    var vadThreshold: Float = -40
    var aecEnabled = false
    var outputBufferMs: UInt32 = 300
    var processingChain = ["AEC", "NoiseReduction", "Dereverb", "Equalizer", "Amplifier", "AGC", "VAD"]
    var equalizer = EqualizerSettings()
}

struct AudioMetricsSnapshot {
    var bitrate = 0
    var sampleRate = 0
    var latencyMs: Int64 = 0
    var networkLatencyMs: Int64 = 0
    var packetLossRate = 0.0
    var jitterMs = 0.0
    var bufferDurationMs: Int64 = 0
}

struct ConnectedDevice: Equatable {
    var name: String
    var ip: String
    var latency: UInt32
}
