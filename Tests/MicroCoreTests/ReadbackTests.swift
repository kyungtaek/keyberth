import XCTest
@testable import MicroCore

final class ReadbackTests: XCTestCase {
    // Independent literal wire fixture: 0x06 report ID, 0x02 channel, 33-byte payload.
    private let literal = #"{"id":7,"result":{"version":"x"}}"# + "\n"
    private func fixture(_ payload: String) -> [UInt8] {
        let bytes = Array(payload.utf8)
        return [0x06, 0x02, UInt8(bytes.count)] + bytes + Array(repeating: 0, count: 61 - bytes.count)
    }
    func testExplicitReportConventions() throws {
        let bytes = fixture(literal)
        var full = Readback()
        XCTAssertEqual(try full.accept(id: 6, bytes: bytes), Data(literal.utf8))
        var separate = Readback()
        XCTAssertEqual(try separate.accept(id: 6, bytes: Array(bytes.dropFirst())), Data(literal.utf8))
        var invalid = Readback()
        XCTAssertThrowsError(try invalid.accept(id: 1, bytes: bytes))
        var corrupted = bytes
        corrupted[63] = 1
        XCTAssertThrowsError(try invalid.accept(id: 6, bytes: corrupted))
    }
    func testInputNotificationsCannotStandInForProbeReplies() throws {
        let event = #"{"method":"v.oai.hid","params":{"k":"AG05","ag":5,"act":1}}"#
        let rad = #"{"method":"v.oai.rad","params":{"a":0.75,"d":1}}"#
        for payload in [event, rad] {
            let data = Data(payload.utf8)
            XCTAssertTrue(ProbeReply.isInputNotification(data))
            XCTAssertThrowsError(try ProbeReply.version(data, id: 7))
        }
        for payload in [#"{"id":7,"method":"v.oai.hid","params":{}}"#, #"{"method":"v.oai.hid"}"#,
                        #"{"method":"unknown","params":{}}"#, literal] {
            XCTAssertFalse(ProbeReply.isInputNotification(Data(payload.utf8)))
        }
    }
    func testCorrelationAndFragments() throws {
        var rx = Readback()
        XCTAssertNil(try rx.accept(id: 6, bytes: fixture(#"{"id":7,"result":"#)))
        let payload = try XCTUnwrap(rx.accept(id: 6, bytes: fixture(#"{"version":"x"}}"# + "\n")))
        XCTAssertNoThrow(try ProbeReply.version(payload, id: 7))
        XCTAssertThrowsError(try ProbeReply.version(payload, id: 8))
        XCTAssertEqual(try ProbeReply.version(payload, id: 7), "x")
    }
}
