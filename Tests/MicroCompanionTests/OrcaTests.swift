import XCTest
import MicroCore
@testable import MicroCompanion

final class OrcaTests: XCTestCase {
    func testCatalogAndPresetRoundTrip() throws {
        XCTAssertEqual(OrcaCatalog.byBinding.count,164)
        let p=AppProfile.orca, preset=KeyMap.preset(p)
        XCTAssertEqual(preset.count,14)
        XCTAssertEqual(preset["ENC_PRESS"],"orca.floatingTerminal.toggle")
        XCTAssertTrue(KeyMap.keys.prefix(6).allSatisfy { preset[$0] == nil })
        let archive=KeymapArchive(version:1,profiles:[p.rawValue:preset],claudeSlots:nil)
        try JSONDecoder().decode(KeymapArchive.self,from:JSONEncoder().encode(archive)).validate()
        for (id,action) in OrcaCatalog.byBinding {
            XCTAssertTrue(KeymapArchive.accepts(id,input:"K07",profile:p))
            if !action.defaults.isEmpty {
                XCTAssertNoThrow(try OrcaControls.chord(for:action,overrides:[:]),id)
            }
        }
    }
    func testIndexedBindingsAndUnboundCommands() throws {
        let slot=try XCTUnwrap(OrcaCatalog.byBinding["orca.workspace.selectByIndex.6"])
        XCTAssertEqual(try OrcaControls.chord(for:slot,overrides:[slot.id:"Ctrl+Digit1"]),"ctrl+6")
        let board=try XCTUnwrap(OrcaCatalog.byBinding["orca.workspace.openBoard"])
        XCTAssertThrowsError(try OrcaControls.chord(for:board,overrides:[:]))
        XCTAssertEqual(try OrcaControls.chord(for:board,overrides:[board.id:["Mod+Shift+B"]]),"cmd+shift+b")
        XCTAssertThrowsError(try OrcaControls.chord(for:slot,overrides:[slot.id:NSNull()]))
    }
}
