import Foundation

/// Small, dependency-free proto3 wire codec for the message types documented in PROTOCOL.md.
/// It intentionally handles only the protocol's field schema; unknown fields are skipped.
public enum MicYouProtobufCodec {
    public static func encode(_ message: MicYouMessage) -> Data {
        var nested = ProtoWriter()
        var wrapper = ProtoWriter()

        switch message {
        case .audio(let packet):
            nested = encodeOrderedAudio(packet)
            wrapper.bytes(field: 1, nested.data)
        case .connect(let sessionID):
            nested.int64(field: 1, sessionID)
            wrapper.bytes(field: 2, nested.data)
        case .mute(let isMuted):
            if let isMuted { nested.optionalBool(field: 1, isMuted) }
            wrapper.bytes(field: 3, nested.data)
        case .ping(let timestamp):
            nested.int64(field: 1, timestamp)
            wrapper.bytes(field: 5, nested.data)
        case .pong(let timestamp):
            nested.int64(field: 1, timestamp)
            wrapper.bytes(field: 6, nested.data)
        case .plugin(let plugin):
            nested = encodePlugin(plugin)
            wrapper.bytes(field: 7, nested.data)
        }
        return wrapper.data
    }

    public static func decode(_ data: Data) throws -> MicYouMessage {
        let fields = try ProtoReader(data).allFields()
        for field in fields {
            guard field.wireType == 2, let bytes = field.bytes else { continue }
            switch field.number {
            case 1: return .audio(try decodeOrderedAudio(bytes))
            case 2: return .connect(sessionID: try scalar(1, in: bytes).int64Value)
            case 3:
                let mute = try ProtoReader(bytes).allFields().first(where: { $0.number == 1 })
                return .mute(isMuted: mute?.varintValue.map { $0 != 0 })
            case 5: return .ping(timestamp: try scalar(1, in: bytes).int64Value)
            case 6: return .pong(timestamp: try scalar(1, in: bytes).int64Value)
            case 7: return .plugin(try decodePlugin(bytes))
            default: continue
            }
        }
        throw MicYouProtocolError.missingRequiredMessage
    }

    private static func encodeOrderedAudio(_ packet: MicYouOrderedAudioPacket) -> ProtoWriter {
        var writer = ProtoWriter()
        writer.int32(field: 1, packet.sequenceNumber)
        writer.bytes(field: 2, encodeAudioPacket(packet.audioPacket).data)
        writer.int64(field: 3, packet.timestamp)
        writer.bytes(field: 4, packet.fecBuffer)
        writer.int32(field: 5, packet.fecSequenceNumber)
        writer.int64(field: 6, packet.sessionID)
        for length in packet.fecPacketLengths { writer.uint32(field: 7, length) }
        return writer
    }

    private static func encodeAudioPacket(_ packet: MicYouAudioPacket) -> ProtoWriter {
        var writer = ProtoWriter()
        writer.bytes(field: 1, packet.buffer)
        writer.int32(field: 2, packet.sampleRate)
        writer.int32(field: 3, packet.channelCount)
        writer.int32(field: 4, packet.audioFormat)
        writer.int32(field: 5, packet.codec)
        return writer
    }

    private static func encodePlugin(_ plugin: MicYouPluginMessage) -> ProtoWriter {
        var writer = ProtoWriter()
        writer.string(field: 1, plugin.source)
        writer.string(field: 2, plugin.target)
        writer.string(field: 3, plugin.topic)
        writer.bytes(field: 4, plugin.payload)
        writer.uint64(field: 5, plugin.correlationID)
        writer.bool(field: 6, plugin.isResponse)
        writer.int32(field: 7, plugin.errorCode)
        writer.string(field: 8, plugin.errorMessage)
        return writer
    }

    private static func decodeOrderedAudio(_ data: Data) throws -> MicYouOrderedAudioPacket {
        var sequence: Int32 = 0
        var audio = MicYouAudioPacket(buffer: Data(), sampleRate: 0, channelCount: 0)
        var timestamp: Int64 = 0
        var fecBuffer = Data()
        var fecSequence: Int32 = 0
        var sessionID: Int64 = 0
        var fecLengths: [UInt32] = []

        for field in try ProtoReader(data).allFields() {
            switch (field.number, field.wireType) {
            case (1, 0): sequence = Int32(truncatingIfNeeded: field.varintValue!)
            case (2, 2): audio = try decodeAudioPacket(field.bytes!)
            case (3, 0): timestamp = Int64(bitPattern: field.varintValue!)
            case (4, 2): fecBuffer = field.bytes!
            case (5, 0): fecSequence = Int32(truncatingIfNeeded: field.varintValue!)
            case (6, 0): sessionID = Int64(bitPattern: field.varintValue!)
            case (7, 0): fecLengths.append(UInt32(truncatingIfNeeded: field.varintValue!))
            case (7, 2):
                var packedReader = ProtoReader(field.bytes!)
                fecLengths.append(contentsOf: try packedReader.allVarints().map(UInt32.init(truncatingIfNeeded:)))
            default: continue
            }
        }
        return MicYouOrderedAudioPacket(
            sequenceNumber: sequence,
            audioPacket: audio,
            timestamp: timestamp,
            fecBuffer: fecBuffer,
            fecSequenceNumber: fecSequence,
            sessionID: sessionID,
            fecPacketLengths: fecLengths
        )
    }

    private static func decodeAudioPacket(_ data: Data) throws -> MicYouAudioPacket {
        var buffer = Data()
        var sampleRate: Int32 = 0
        var channelCount: Int32 = 0
        var audioFormat: Int32 = 0
        var codec: Int32 = 0
        for field in try ProtoReader(data).allFields() {
            guard field.wireType == 0 || field.wireType == 2 else { continue }
            switch field.number {
            case 1 where field.wireType == 2: buffer = field.bytes!
            case 2 where field.wireType == 0: sampleRate = Int32(truncatingIfNeeded: field.varintValue!)
            case 3 where field.wireType == 0: channelCount = Int32(truncatingIfNeeded: field.varintValue!)
            case 4 where field.wireType == 0: audioFormat = Int32(truncatingIfNeeded: field.varintValue!)
            case 5 where field.wireType == 0: codec = Int32(truncatingIfNeeded: field.varintValue!)
            default: continue
            }
        }
        return MicYouAudioPacket(buffer: buffer, sampleRate: sampleRate, channelCount: channelCount, audioFormat: audioFormat, codec: codec)
    }

    private static func decodePlugin(_ data: Data) throws -> MicYouPluginMessage {
        var source = ""
        var target = ""
        var topic = ""
        var payload = Data()
        var correlationID: UInt64 = 0
        var isResponse = false
        var errorCode: Int32 = 0
        var errorMessage = ""

        for field in try ProtoReader(data).allFields() {
            switch (field.number, field.wireType) {
            case (1, 2): source = try field.stringValue()
            case (2, 2): target = try field.stringValue()
            case (3, 2): topic = try field.stringValue()
            case (4, 2): payload = field.bytes!
            case (5, 0): correlationID = field.varintValue!
            case (6, 0): isResponse = field.varintValue! != 0
            case (7, 0): errorCode = Int32(truncatingIfNeeded: field.varintValue!)
            case (8, 2): errorMessage = try field.stringValue()
            default: continue
            }
        }
        return MicYouPluginMessage(source: source, target: target, topic: topic, payload: payload, correlationID: correlationID, isResponse: isResponse, errorCode: errorCode, errorMessage: errorMessage)
    }

    private static func scalar(_ number: Int, in data: Data) throws -> ProtoField {
        guard let field = try ProtoReader(data).allFields().first(where: { $0.number == number && $0.wireType == 0 }) else {
            return ProtoField(number: number, wireType: 0, varintValue: 0, bytes: nil)
        }
        return field
    }
}

private struct ProtoWriter {
    private(set) var data = Data()

    mutating func int32(field: Int, _ value: Int32) {
        guard value != 0 else { return }
        key(field, wire: 0)
        appendVarint(UInt64(bitPattern: Int64(value)))
    }

    mutating func int64(field: Int, _ value: Int64) {
        guard value != 0 else { return }
        key(field, wire: 0)
        appendVarint(UInt64(bitPattern: value))
    }

    mutating func uint32(field: Int, _ value: UInt32) {
        guard value != 0 else { return }
        key(field, wire: 0)
        appendVarint(UInt64(value))
    }

    mutating func uint64(field: Int, _ value: UInt64) {
        guard value != 0 else { return }
        key(field, wire: 0)
        appendVarint(value)
    }

    mutating func bool(field: Int, _ value: Bool) {
        guard value else { return }
        key(field, wire: 0)
        appendVarint(1)
    }

    mutating func optionalBool(field: Int, _ value: Bool) {
        key(field, wire: 0)
        appendVarint(value ? 1 : 0)
    }

    mutating func string(field: Int, _ value: String) {
        guard !value.isEmpty else { return }
        bytes(field: field, Data(value.utf8))
    }

    mutating func bytes(field: Int, _ value: Data) {
        guard !value.isEmpty else { return }
        key(field, wire: 2)
        appendVarint(UInt64(value.count))
        data.append(value)
    }

    private mutating func key(_ field: Int, wire: UInt8) {
        appendVarint(UInt64((field << 3) | Int(wire)))
    }

    private mutating func appendVarint(_ value: UInt64) {
        var remaining = value
        while remaining >= 0x80 {
            data.append(UInt8(remaining & 0x7f) | 0x80)
            remaining >>= 7
        }
        data.append(UInt8(remaining))
    }
}

private struct ProtoField {
    let number: Int
    let wireType: UInt8
    let varintValue: UInt64?
    let bytes: Data?

    var int64Value: Int64 { Int64(bitPattern: varintValue ?? 0) }

    func stringValue() throws -> String {
        guard let bytes, let value = String(data: bytes, encoding: .utf8) else { throw MicYouProtocolError.invalidUTF8 }
        return value
    }
}

private struct ProtoReader {
    private let data: Data
    private var offset = 0

    init(_ data: Data) { self.data = data }

    mutating func allVarints() throws -> [UInt64] {
        var values: [UInt64] = []
        while offset < data.count { values.append(try readVarint()) }
        return values
    }

    func allFields() throws -> [ProtoField] {
        var reader = self
        var fields: [ProtoField] = []
        while reader.offset < reader.data.count {
            let key = try reader.readVarint()
            let number = Int(key >> 3)
            let wireType = UInt8(key & 0x7)
            guard number > 0 else { throw MicYouProtocolError.malformedProtobuf }
            switch wireType {
            case 0:
                fields.append(ProtoField(number: number, wireType: wireType, varintValue: try reader.readVarint(), bytes: nil))
            case 1:
                try reader.skip(8)
                fields.append(ProtoField(number: number, wireType: wireType, varintValue: nil, bytes: nil))
            case 2:
                let length = try reader.readVarint()
                guard length <= UInt64(Int.max) else { throw MicYouProtocolError.malformedProtobuf }
                let bytes = try reader.readBytes(Int(length))
                fields.append(ProtoField(number: number, wireType: wireType, varintValue: nil, bytes: bytes))
            case 5:
                try reader.skip(4)
                fields.append(ProtoField(number: number, wireType: wireType, varintValue: nil, bytes: nil))
            default:
                throw MicYouProtocolError.malformedProtobuf
            }
        }
        return fields
    }

    private mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        for shift in stride(from: 0, through: 63, by: 7) {
            guard offset < data.count else { throw MicYouProtocolError.malformedProtobuf }
            let byte = data[offset]
            offset += 1
            if shift == 63 && byte > 1 { throw MicYouProtocolError.malformedProtobuf }
            result |= UInt64(byte & 0x7f) << UInt64(shift)
            if byte & 0x80 == 0 { return result }
        }
        throw MicYouProtocolError.malformedProtobuf
    }

    private mutating func readBytes(_ length: Int) throws -> Data {
        guard length >= 0, length <= data.count - offset else { throw MicYouProtocolError.malformedProtobuf }
        defer { offset += length }
        return data.subdata(in: offset..<(offset + length))
    }

    private mutating func skip(_ length: Int) throws {
        _ = try readBytes(length)
    }
}
