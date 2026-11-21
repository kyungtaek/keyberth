import XCTest
import MicroCore
@testable import MicroCompanion

final class SessionActivityTests: XCTestCase {
    func testFourthSlotKeepsRankAcrossFocusReadAndReload() throws {
        var activity = SessionActivity()
        for i in 1...6 {
            _ = activity.observe(id:String(i),light:.ready,initialTime:Double(7-i),now:10)
        }
        for light in [SessionLight.active, .unknown, .ready] {
            XCTAssertEqual(activity.observe(id:"4",light:light,initialTime:25,now:30),3)
        }
        let saved = try JSONEncoder().encode(activity.entries)
        activity = SessionActivity(entries:try JSONDecoder().decode([String:SessionActivity.Entry].self,from:saved))
        func order() -> [String] {
            activity.entries.keys.sorted { activity.entries[$0]!.time > activity.entries[$1]!.time }
        }
        XCTAssertEqual(order(),["1","2","3","4","5","6"])
        XCTAssertEqual(activity.observe(id:"4",light:.running,now:40),40)
        XCTAssertEqual(order().first,"4")
        XCTAssertEqual(activity.observe(id:"4",light:.attention,now:45),45)
        XCTAssertEqual(activity.observe(id:"4",light:.done,revision:"a",now:50),50)
        XCTAssertEqual(activity.observe(id:"4",light:.done,revision:"a",now:60),50)
        XCTAssertEqual(activity.observe(id:"4",light:.done,revision:"b",now:70),70)
    }
}
