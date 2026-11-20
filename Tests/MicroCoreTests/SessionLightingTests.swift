import XCTest
@testable import MicroCore

final class SessionLightingTests: XCTestCase {
    func testFrameRetainsSevenStateDistinctionsAndSelectsAmbient() throws {
        var rules = SessionLighting.initial.rules
        for (i,state) in SessionLight.allCases.enumerated() {
            let style = SessionLighting.Style(color:String(format:"#%06X",i+1),effect:i)
            rules[state.rawValue] = .init(slot:style,ambient:style)
        }
        let palette = SessionLighting(rules:rules)
        let states: [SessionLight] = [.active,.ready,.empty,.unknown,.attention,.done]
        func unpack(_ packets:[[UInt8]]) throws -> [String:Any] {
            var input=Readback()
            for packet in packets {
                if let data=try input.accept(id:6,bytes:packet) { return try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any]) }
            }
            XCTFail("Incomplete HID packet"); return [:]
        }
        for (selection,expected) in [(4,SessionLight.attention),(0,.active),(2,.attention),(-1,.attention)] {
            let messages=try palette.commands(states:states,selected:selection,firstID:70)
            let keys=try unpack(messages[0]), glow=try unpack(messages[1])
            XCTAssertEqual(keys["id"] as? Int,70)
            XCTAssertEqual(glow["id"] as? Int,71)
            let slots=try XCTUnwrap(keys["params"] as? [[String:Any]])
            XCTAssertEqual(slots.compactMap { $0["id"] as? Int },Array(0..<6))
            XCTAssertEqual(slots.compactMap { $0["e"] as? Int },states.map { rules[$0.rawValue]!.slot.effect })
            let params=try XCTUnwrap(glow["params"] as? [String:[String:Any]])
            XCTAssertEqual(params["ambient"]?["e"] as? Int,rules[expected.rawValue]?.ambient.effect)
        }
    }
    func testInvalidSavedRuleIsRejected() {
        var rules=SessionLighting.initial.rules
        let invalid=SessionLighting.Style(color:"#GG00DD",effect:7)
        rules[SessionLight.ready.rawValue] = .init(slot:invalid,ambient:invalid)
        XCTAssertFalse(SessionLighting(rules:rules).valid)
        XCTAssertFalse(SessionLighting(rules:[:]).valid)
        XCTAssertThrowsError(try SessionLighting.initial.commands(states:[],selected:nil,firstID:1))
    }

    func testFirmwareOwnsOneRunningSlotWhileOtherColorsAreWritten() throws {
        let states: [SessionLight] = [.running,.ready,.running,.empty,.empty,.empty]
        let palette = SessionLighting.initial
        XCTAssertEqual(palette.breathingSlot(states:states,viewed:2),2)
        XCTAssertEqual(palette.breathingSlot(states:states,viewed:1),0)
        XCTAssertNil(palette.breathingSlot(states:[.ready],viewed:nil))
        let packets = try palette.commands(states:states,selected:2,firstID:1,firmwareSlot:2)[0]
        var input = Readback()
        let data = try XCTUnwrap(try packets.compactMap { try input.accept(id:6,bytes:$0) }.first)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        let slots = try XCTUnwrap(object["params"] as? [[String:Any]])
        XCTAssertEqual(slots.compactMap { $0["id"] as? Int },[0,1,3,4,5])
    }
}
