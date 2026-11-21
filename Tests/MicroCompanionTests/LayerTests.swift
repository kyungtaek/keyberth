import XCTest
import MicroCore
@testable import MicroCompanion

final class LayerTests:XCTestCase {
    func testGlobalInheritanceAndExplicitAppOverrides() {
        XCTAssertNil(KeyMap.localBinding(nil))
        XCTAssertNil(KeyMap.localBinding("inherit"))
        XCTAssertEqual(KeyMap.localBinding("none"),"none")
        XCTAssertEqual(KeyMap.localBinding("agent.stop"),"agent.stop")
    }

    func testSharedBindingsArchive() throws {
        let archive=KeymapArchive(global:["K12":"system.missionControl","ENC_CW":"allRecent.6"],version:2,
                                  profiles:["codex":["K12":"inherit"],"cmux":["K01":"allRecent.3"]],claudeSlots:nil)
        let copy=try JSONDecoder().decode(KeymapArchive.self,from:JSONEncoder().encode(archive))
        try copy.validate()
        XCTAssertEqual(copy.global,archive.global)
        XCTAssertFalse(KeymapArchive.common("agent.stop"))
        XCTAssertFalse(KeymapArchive.common("allRecent.7"))
    }
}
