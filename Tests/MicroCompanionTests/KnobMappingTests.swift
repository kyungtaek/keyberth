import XCTest
import MicroCore
@testable import MicroCompanion

final class KnobMappingTests: XCTestCase {
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
