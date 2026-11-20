import Foundation
import XCTest
@testable import MicroCompanion

final class CodexTurnTests: XCTestCase {
    func testNewestTurnControlsEachSlotAcrossPolls() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:home) }
        let file = directory.appendingPathComponent("thread_history_1.sqlite")
        let thread = UUID(), id = thread.uuidString.lowercased(), missing = UUID()
        func execute(_ sql:String) throws {
            _ = try CmuxClient.run([file.path,sql],executable:"/usr/bin/sqlite3")
        }
        XCTAssertTrue(DesktopSessions.latestCodexTurns([thread],home:home).isEmpty)
        try execute("""
            CREATE TABLE thread_turns(thread_id TEXT,turn_id TEXT,rollout_ordinal INTEGER,status TEXT);
            INSERT INTO thread_turns VALUES ('\(id)','old',4,'completed'),('\(id)','current',18,'inProgress');
            """)
        let live = DesktopSessions.latestCodexTurns([thread,missing],home:home)
        XCTAssertEqual(live[id]?.0,.running)
        XCTAssertNil(live[missing.uuidString.lowercased()])
        try execute("UPDATE thread_turns SET status='completed' WHERE turn_id='current'")
        let final = DesktopSessions.latestCodexTurns([thread],home:home)
        XCTAssertEqual(final[id]?.0,.done)
        XCTAssertEqual(final[id]?.1,"current")
    }
}
