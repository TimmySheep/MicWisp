import Foundation

public struct MicYouFrameDecoder {
    public static let tcpMagic: UInt32 = 0x4D69_6359
    public static let udpMagic: UInt32 = 0x4D69_6355
    public static let headerLength = 8
    public static let maximumControlPayloadLength = 1024 * 1024

    private var buffer = Data()

    public init() {}

    public mutating func append(_ bytes: Data, expectedMagic: UInt32 = Self.tcpMagic) throws -> [Data] {
        if !bytes.isEmpty { buffer.append(bytes) }
        var payloads: [Data] = []

        while buffer.count >= Self.headerLength {
            let magic = buffer.readUInt32BE(at: 0)
            guard magic == expectedMagic else { throw MicYouProtocolError.invalidFrameMagic(magic) }
            let rawLength = buffer.readUInt32BE(at: 4)
            guard rawLength <= UInt32(Int32.max) else { throw MicYouProtocolError.negativeFrameLength }
            let length = Int(rawLength)
            guard length <= Self.maximumControlPayloadLength else { throw MicYouProtocolError.frameTooLarge(length) }
            let frameLength = Self.headerLength + length
            guard buffer.count >= frameLength else { break }
            payloads.append(buffer.subdata(in: Self.headerLength..<frameLength))
            buffer.removeSubrange(0..<frameLength)
        }

        guard buffer.count <= Self.maximumControlPayloadLength + Self.headerLength else {
            throw MicYouProtocolError.frameTooLarge(buffer.count - Self.headerLength)
        }
        return payloads
    }

    public var bufferedByteCount: Int { buffer.count }

    public static func encode(payload: Data, magic: UInt32 = tcpMagic) throws -> Data {
        guard payload.count <= maximumControlPayloadLength else { throw MicYouProtocolError.frameTooLarge(payload.count) }
        var data = Data(capacity: headerLength + payload.count)
        data.appendUInt32BE(magic)
        data.appendUInt32BE(UInt32(payload.count))
        data.append(payload)
        return data
    }
}

private extension Data {
    func readUInt32BE(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
    }

    mutating func appendUInt32BE(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }
}
