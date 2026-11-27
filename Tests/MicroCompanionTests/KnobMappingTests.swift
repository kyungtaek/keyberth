import XCTest
import MicroCore
@testable import MicroCompanion

final class KnobMappingTests: XCTestCase {
    func testFavoriteCycleWrapsAndEntersFromAnotherApp() {
        let apps = ["z":"Alpha", "a":"Beta"]
        func next(_ id:String?, forward:Bool = true) -> String? {
            MacActions.adjacentFavorite(forward:forward,current:id,apps:apps)
        }
        XCTAssertEqual(next("z"),"a")
        XCTAssertEqual(next("a"),"z")
        XCTAssertEqual(next("z",forward:false),"a")
        XCTAssertEqual(next(nil),"z")
        XCTAssertEqual(next("other",forward:false),"a")
        XCTAssertNil(MacActions.adjacentFavorite(forward:true,current:nil,apps:[:]))
    }

    func testNavigationActionsAreAvailableInBothLayers() throws {
        for action in ["system.scrollUp","system.scrollDown","system.pageUp","system.pageDown","apps.nextFavorite","apps.previousFavorite"] {
            try KeymapArchive(global:["ENC_CW":action],version:2,profiles:["cmux":["K07":action]],claudeSlots:nil).validate()
        }
    }

    func testCodexPickerActionsCanBeAssignedToKnob() throws {
        for step in [CodexControls.PickerStep.next, .previous, .up, .down] {
            XCTAssertNotNil(AppProfile.codex.agentActions[step.rawValue])
            XCTAssertNil(AppProfile.t3.agentActions[step.rawValue])
            let archive = KeymapArchive(version:1, profiles:["codex":["ENC_CW":step.rawValue]], claudeSlots:nil)
            try archive.validate()
        }
    }
    func testKnobOverridesRoundTripAcrossProfiles() throws {
        let profiles = [
            "cmux": ["ENC_CCW":"JOY_LEFT", "ENC_CW":"JOY_RIGHT", "ENC_PRESS":"K13"],
            "codex": ["ENC_CCW":"recent.1", "ENC_CW":"cmd+shift+k", "ENC_PRESS":"agent.newChat"]
        ]
        let archive = KeymapArchive(version:1, profiles:profiles, claudeSlots:nil)
        let restored = try JSONDecoder().decode(KeymapArchive.self, from:JSONEncoder().encode(archive))
        try restored.validate()
        XCTAssertEqual(restored.profiles, profiles)
    }
}
