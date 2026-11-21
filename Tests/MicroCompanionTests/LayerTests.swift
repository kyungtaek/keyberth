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

    func testFrequentAppPresets() {
        for profile:AppProfile in [.codex,.t3,.cmux] {
            let preset=KeyMap.preset(profile)
            XCTAssertTrue(Set(KeyMap.keys.prefix(6)).isDisjoint(with:preset.keys))
            XCTAssertTrue(KeyMap.keys.dropFirst(6).allSatisfy { preset[$0] != nil })
            XCTAssertTrue(preset.allSatisfy { KeymapArchive.accepts($0.value,input:$0.key,profile:profile) })
        }
        XCTAssertEqual(KeyMap.preset(.t3)["K12"],"agent.stop")
        XCTAssertEqual(KeyMap.preset(.codex)["K12"],"agent.newChat")
        XCTAssertEqual(KeyMap.preset(.cmux)["ENC_CW"],"ENC_CW")
        XCTAssertTrue(KeyMap.preset(.application("com.apple.finder")).isEmpty)
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
