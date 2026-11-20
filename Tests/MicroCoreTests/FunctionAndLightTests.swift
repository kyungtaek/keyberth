import XCTest
@testable import MicroCore

final class FunctionAndLightTests: XCTestCase {
    func testMacCommandChords() {
        XCTAssertEqual(FunctionKey.shortcut("ctrl+cmd+k"), "cmd+ctrl+k")
        XCTAssertEqual(FunctionKey.shortcut("cmd+alt+shift+="), "cmd+alt+shift+=")
        XCTAssertEqual(FunctionKey.shortcut("cmd+f"), "cmd+f")
        XCTAssertNil(FunctionKey.shortcut("cmd+cmd+k"))
    }
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
        XCTAssertEqual(SessionLight.ready.rgb,0xFFFFFF)
        XCTAssertEqual(SessionLight.active.rgb,SessionLight.ready.rgb)
        var indicator = CompletionIndicator()
        XCTAssertEqual(indicator.display(.done,id:"a",revision:"1"),.ready)
        XCTAssertEqual(indicator.display(.running,id:"a"),.running)
        XCTAssertEqual(indicator.display(.done,id:"a",revision:"2"),.done)
        indicator.markViewed("a")
        XCTAssertEqual(indicator.display(.done,id:"a",revision:"2"),.ready)
        XCTAssertEqual(indicator.display(.done,id:"a",revision:"3"),.done)
        XCTAssertEqual(SessionLight.empty.rgb, 0)
    }
}
