import Foundation
import XCTest
@testable import MicYouCore

final class ProtocolCodecTests: XCTestCase {
    func testConnectUsesExpectedProtobufFieldNumbers() throws {
        let encoded = MicYouProtobufCodec.encode(.connect(sessionID: 150))
        XCTAssertEqual(Array(encoded), [0x12, 0x03, 0x08, 0x96, 0x01])
        XCTAssertEqual(try MicYouProtobufCodec.decode(encoded), .connect(sessionID: 150))
    }

    func testOptionalMutePreservesExplicitFalse() throws {
        let encoded = MicYouProtobufCodec.encode(.mute(isMuted: false))
        XCTAssertEqual(Array(encoded), [0x1a, 0x02, 0x08, 0x00])
        XCTAssertEqual(try MicYouProtobufCodec.decode(encoded), .mute(isMuted: false))
        XCTAssertEqual(try MicYouProtobufCodec.decode(Data([0x1a, 0x00])), .mute(isMuted: nil))
    }

    func testAudioPacketRoundTripsAllFields() throws {
        let packet = MicYouOrderedAudioPacket(
            sequenceNumber: 42,
            audioPacket: MicYouAudioPacket(buffer: Data([0, 1, 0xfe, 0xff]), sampleRate: 48_000, channelCount: 1, audioFormat: 1),
            timestamp: 1_725_000_123,
            fecBuffer: Data([9, 8]),
            fecSequenceNumber: 40,
            sessionID: 7,
            fecPacketLengths: [12, 300]
        )
        XCTAssertEqual(try MicYouProtobufCodec.decode(MicYouProtobufCodec.encode(.audio(packet))), .audio(packet))
    }

    func testPluginMessageRoundTripsUTF8AndPayload() throws {
        let plugin = MicYouPluginMessage(
            source: "ios-client",
            target: "desktop",
            topic: "status/已连接",
            payload: Data([0, 1, 2, 255]),
            correlationID: UInt64.max,
            isResponse: true,
            errorCode: 3,
            errorMessage: "not available"
        )
        XCTAssertEqual(try MicYouProtobufCodec.decode(MicYouProtobufCodec.encode(.plugin(plugin))), .plugin(plugin))
    }

    func testFrameHeaderIsBigEndianAndStreamDecoderHandlesFragments() throws {
        let payload = Data([0x12, 0x03, 0x08, 0x96, 0x01])
        let frame = try MicYouFrameDecoder.encode(payload: payload)
        XCTAssertEqual(Array(frame.prefix(8)), [0x4d, 0x69, 0x63, 0x59, 0, 0, 0, 5])

        var decoder = MicYouFrameDecoder()
        XCTAssertEqual(try decoder.append(frame.prefix(3)), [])
        XCTAssertEqual(try decoder.append(frame.dropFirst(3)), [payload])
        XCTAssertEqual(decoder.bufferedByteCount, 0)
    }

    func testFrameDecoderReturnsMultipleFramesFromOneRead() throws {
        let first = try MicYouFrameDecoder.encode(payload: Data([1]))
        let second = try MicYouFrameDecoder.encode(payload: Data([2, 3]))
        var decoder = MicYouFrameDecoder()
        XCTAssertEqual(try decoder.append(first + second), [Data([1]), Data([2, 3])])
    }

    func testFrameDecoderRejectsWrongMagicAndOversize() throws {
        var decoder = MicYouFrameDecoder()
        XCTAssertThrowsError(try decoder.append(Data([0, 0, 0, 1, 0, 0, 0, 0])))
        var hugeLength = Data([0x4d, 0x69, 0x63, 0x59, 0, 0x10, 0, 1])
        XCTAssertThrowsError(try decoder.append(hugeLength))
        hugeLength.removeAll()
    }

    func testMalformedProtobufIsRejected() {
        XCTAssertThrowsError(try MicYouProtobufCodec.decode(Data([0x12, 0x05, 0x08])))
        XCTAssertThrowsError(try MicYouProtobufCodec.decode(Data([0x12, 0x80])))
    }
}
