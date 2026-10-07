import Foundation

public enum MicYouCodec: Int32, Sendable {
    case pcm = 0
    case opus = 1
}

public struct MicYouAudioPacket: Equatable, Sendable {
    public var buffer: Data
    public var sampleRate: Int32
    public var channelCount: Int32
    public var audioFormat: Int32
    public var codec: Int32

    public init(
        buffer: Data,
        sampleRate: Int32,
        channelCount: Int32,
        audioFormat: Int32 = 0,
        codec: Int32 = MicYouCodec.pcm.rawValue
    ) {
        self.buffer = buffer
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.audioFormat = audioFormat
        self.codec = codec
    }
}

public struct MicYouOrderedAudioPacket: Equatable, Sendable {
    public var sequenceNumber: Int32
    public var audioPacket: MicYouAudioPacket
    public var timestamp: Int64
    public var fecBuffer: Data
    public var fecSequenceNumber: Int32
    public var sessionID: Int64
    public var fecPacketLengths: [UInt32]

    public init(
        sequenceNumber: Int32,
        audioPacket: MicYouAudioPacket,
        timestamp: Int64,
        fecBuffer: Data = Data(),
        fecSequenceNumber: Int32 = 0,
        sessionID: Int64 = 0,
        fecPacketLengths: [UInt32] = []
    ) {
        self.sequenceNumber = sequenceNumber
        self.audioPacket = audioPacket
        self.timestamp = timestamp
        self.fecBuffer = fecBuffer
        self.fecSequenceNumber = fecSequenceNumber
        self.sessionID = sessionID
        self.fecPacketLengths = fecPacketLengths
    }
}

public struct MicYouPluginMessage: Equatable, Sendable {
    public var source: String
    public var target: String
    public var topic: String
    public var payload: Data
    public var correlationID: UInt64
    public var isResponse: Bool
    public var errorCode: Int32
    public var errorMessage: String

    public init(
        source: String,
        target: String,
        topic: String,
        payload: Data = Data(),
        correlationID: UInt64 = 0,
        isResponse: Bool = false,
        errorCode: Int32 = 0,
        errorMessage: String = ""
    ) {
        self.source = source
        self.target = target
        self.topic = topic
        self.payload = payload
        self.correlationID = correlationID
        self.isResponse = isResponse
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }
}

public enum MicYouMessage: Equatable, Sendable {
    case audio(MicYouOrderedAudioPacket)
    case connect(sessionID: Int64)
    case mute(isMuted: Bool?)
    case ping(timestamp: Int64)
    case pong(timestamp: Int64)
    case plugin(MicYouPluginMessage)
}

public enum MicYouProtocolError: Error, Equatable, LocalizedError {
    case malformedProtobuf
    case invalidUTF8
    case missingRequiredMessage
    case invalidFrameMagic(UInt32)
    case negativeFrameLength
    case frameTooLarge(Int)

    public var errorDescription: String? {
        switch self {
        case .malformedProtobuf: "Malformed Protocol Buffers payload."
        case .invalidUTF8: "A Protocol Buffers string was not valid UTF-8."
        case .missingRequiredMessage: "The message wrapper did not contain a supported message."
        case .invalidFrameMagic(let value): "Unexpected frame magic 0x\(String(value, radix: 16))."
        case .negativeFrameLength: "A frame declared a negative payload length."
        case .frameTooLarge(let value): "Frame payload length \(value) exceeds the configured limit."
        }
    }
}
