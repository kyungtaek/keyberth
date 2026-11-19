import XCTest
@testable import MicroCore

final class CmuxTests: XCTestCase {
    func testSurfaceIdentitySurvivesReorderButNotWorkspaceMove() throws {
        let window = UUID(), workspace = UUID(), first = UUID(), second = UUID()
        func tree(_ ids: [UUID], in space: UUID) throws -> [CmuxTarget] {
            var surfaces: [[String: Any]] = ids.map {
                ["type": "terminal", "title": "shell", "id": $0.uuidString, "active": $0 == first]
            }
            surfaces.append(["type": "browser", "id": UUID().uuidString])
            let data = try JSONSerialization.data(withJSONObject: ["windows": [[
                "id": window.uuidString, "workspaces": [["id": space.uuidString, "title": "work", "panes": [["surfaces": surfaces]]]]
            ]]])
            return try CmuxTarget.targets(data)
        }
        let original = try tree([first, second], in: workspace)
        let reordered = try tree([second, first], in: workspace)
        XCTAssertEqual(original.map(\.id), [first, second])
        XCTAssertEqual(original.map(\.active), [true, false])
        XCTAssertTrue(original[0].sameLocation(as: reordered[1]))
        XCTAssertFalse(original[0].sameLocation(as: reordered[0]))
        XCTAssertFalse(try original[0].sameLocation(as: tree([first], in: UUID())[0]))
    }
}
