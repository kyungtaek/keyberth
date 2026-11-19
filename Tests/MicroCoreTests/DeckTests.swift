import XCTest
@testable import MicroCore

final class DeckTests: XCTestCase {
    func testPhysicalInputs() {
        for n in 1...13 { XCTAssertEqual(DeckInput(id: String(format: "K%02d", n)), .key(n)) }
        XCTAssertEqual(DeckInput(id: "ENC_CCW"), .turn(-1))
        XCTAssertEqual(DeckInput(id: "ENC_CW"), .turn(1))
        for d in ["left","right","up","down"] { XCTAssertEqual(DeckInput(id: "JOY_" + d.uppercased()), .direction(d)) }
        XCTAssertEqual(DeckInput(id: "ENC_PRESS"), .knobPress)
        XCTAssertNil(DeckInput(id: "JOY_UNKNOWN"))
    }
    func testRecentSessionsExcludeClosedAndKeepSix() {
        let w = UUID(), ws = UUID()
        let live = (0..<8).map { CmuxTarget(id: UUID(), window: w, workspace: ws, title: String($0), active: $0 == 7) }
        XCTAssertEqual(Deck.recent(live: live, history: [UUID(),live[6].id,live[7].id]).map(\.title), ["7","6","0","1","2","3"])
    }
}
