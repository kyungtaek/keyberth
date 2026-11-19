import XCTest
@testable import MicroCore

final class FunctionAndLightTests: XCTestCase {
    func testFunctionKeysOnlyDispatchDownForExactPhysicalPositions() {
        func event(_ key: String, _ action: Int) -> Data {
            Data("{\"method\":\"v.oai.hid\",\"params\":{\"k\":\"\(key)\",\"act\":\(action)}}".utf8)
        }
        for number in 6...12 {
            let key = String(format: "ACT%02d", number)
            XCTAssertEqual(FunctionKey.index(in: event(key, 1)), number)
            XCTAssertNil(FunctionKey.index(in: event(key, 0)))
        }
        for other in ["AG01", "ACT6", "ACT13"] { XCTAssertNil(FunctionKey.index(in: event(other, 1))) }
    }
    func testTerminalChordValidation() {
        XCTAssertEqual(FunctionKey.shortcut(" Alt+Ctrl+A "), "ctrl+alt+a")
        XCTAssertEqual(FunctionKey.shortcut("Escape"), "escape")
        for invalid in ["a", "ctrl+ctrl+a", "ctrl+", "ctrl+echo hello", "--force", "enter\nls"] {
            XCTAssertNil(FunctionKey.shortcut(invalid))
        }
    }
    func testWorkspaceStatePriorityAndPhysicalColour() throws {
        func light(_ needsInput: Bool, _ running: Bool, _ lane: String, _ active: Bool) throws -> SessionLight {
            let data = try JSONSerialization.data(withJSONObject: [
                "workspace_id": UUID().uuidString, "effective": lane,
                "signals": ["any_agent_needs_input": needsInput, "any_agent_running": running]
            ])
            return try JSONDecoder().decode(WorkspaceSignal.self, from: data).light(active: active)
        }
        XCTAssertEqual(try light(true, true, "done", true), .attention)
        XCTAssertEqual(try light(false, true, "todo", false), .running)
        XCTAssertEqual(try light(false, false, "done", false), .done)
        XCTAssertEqual(try light(false, false, "todo", true), .active)
        XCTAssertEqual(try light(false, false, "todo", false), .ready)
        XCTAssertEqual(Set(SessionLight.allCases.map(\.rgb)).count, SessionLight.allCases.count)
        XCTAssertEqual(SessionLight.empty.rgb, 0)
    }
}
