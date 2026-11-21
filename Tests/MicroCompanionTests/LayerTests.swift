import XCTest
import MicroCore
@testable import MicroCompanion

final class LayerTests:XCTestCase {
    func testGlobalInheritanceAndExplicitAppOverrides() {
        for p in AppProfile.allCases {
            XCTAssertNil(KeyMap.localBinding("K01",profile:p,saved:nil,global:nil))
            XCTAssertNil(KeyMap.localBinding("K12",profile:p,saved:nil,global:"system.missionControl"))
            XCTAssertNil(KeyMap.localBinding("K12",profile:p,saved:"inherit",global:nil))
            XCTAssertEqual(KeyMap.localBinding("K12",profile:p,saved:"none",global:"system.missionControl"),"none")
        }
        XCTAssertEqual(KeyMap.localBinding("K12",profile:.codex,saved:nil,global:nil),"agent.newChat")
        XCTAssertEqual(KeyMap.localBinding("K12",profile:.t3,saved:"agent.stop",global:"system.missionControl"),"agent.stop")
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
