import XCTest
@testable import MicroCore
final class MicroTests: XCTestCase {
    func testIdentityAndStaleGeneration() {
        var state = Slots()
        let a = Key(environment: "a", thread: "same")
        let b = Key(environment: "b", thread: "same")
        let first = state.update([a], now: 1)
        XCTAssertEqual(state.resolve(0, generation: first, now: 2), a)
        let second = state.update([b], now: 2)
        XCTAssertNil(state.resolve(0, generation: first, now: 2))
        XCTAssertEqual(state.resolve(0, generation: second, now: 2), b)
        XCTAssertNil(state.resolve(0, generation: second, now: 10))
        state.disconnect()
        XCTAssertNil(state.resolve(0, generation: second, now: 2))
    }
    func testOnlyMatchingAgentKeyDownNavigates() {
        XCTAssertEqual(Input.slot(in: Data(#"{"method":"v.oai.hid","params":{"k":"AG05","ag":5,"act":1}}"#.utf8)), 5)
        for payload in [
            #"{"method":"v.oai.hid","params":{"k":"AG05","ag":4,"act":1}}"#,
            #"{"method":"v.oai.hid","params":{"k":"AG05","ag":5,"act":0}}"#,
            #"{"method":"v.oai.hid","params":{"k":"AG05","ag":5,"act":true}}"#,
            #"{"method":"v.oai.hid","params":{"k":"ACT06","ag":5,"act":1}}"#
        ] {
            XCTAssertNil(Input.slot(in: Data(payload.utf8)))
        }
    }
    func testProbeFramesAreReadOnly() throws {
        for method in [Probe.version, .status] {
            let frames = try method.frames(id: 9)
            XCTAssertEqual(frames.count, 1)
            let report = frames[0]
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(report.dropFirst(3).prefix(Int(report[2])))) as? [String: Any])
            XCTAssertEqual(Set(json.keys), ["id", "method"])
            XCTAssertEqual(json["id"] as? Int, 9)
            XCTAssertEqual(json["method"] as? String, method.rawValue)
        }
    }
    func testLEDBatchFrames() throws {
        let frames = try LED.frames([0xFF0000, 0, 0, 0, 0, 0])
        XCTAssertGreaterThan(frames.count, 1)
        for frame in frames {
            XCTAssertEqual(frame.count, 64)
            XCTAssertEqual(Array(frame.prefix(2)), [6, 2])
            XCTAssertLessThanOrEqual(frame[2], 61)
        }
        let payload = Data(frames.flatMap { $0.dropFirst(3).prefix(Int($0[2])) })
        XCTAssertEqual(payload.last, 10)
        let rpc = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        XCTAssertEqual(rpc["method"] as? String, "v.oai.thstatus")
        let params = try XCTUnwrap(rpc["params"] as? [[String: Int]])
        XCTAssertEqual(params.map { $0["id"] }, (0...5).map(Optional.some))
        XCTAssertEqual(params[0]["c"], 0xFF0000)
        XCTAssertThrowsError(try LED.frames([0]))
    }
}
