import Foundation
import XCTest
@testable import MicroCompanion

final class AppSwitchHUDTests: XCTestCase {
    func testDefaultAndPersistedChoiceOnlyAffectAppSwitches() throws {
        let name = "KeyberthAppSwitchHUDTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let setting = AppSwitchHUDSetting(preferences: defaults)
        XCTAssertTrue(setting.isEnabled)
        XCTAssertTrue(setting.allows(.appSwitch))
        XCTAssertTrue(setting.allows(.manual))
        XCTAssertFalse(setting.allows(.silent))

        setting.isEnabled = false
        XCTAssertFalse(setting.allows(.appSwitch))
        XCTAssertTrue(setting.allows(.manual))
        XCTAssertFalse(try AppSwitchHUDSetting(preferences: XCTUnwrap(UserDefaults(suiteName: name))).isEnabled)

        setting.isEnabled = true
        XCTAssertTrue(setting.allows(.appSwitch))
    }
}
