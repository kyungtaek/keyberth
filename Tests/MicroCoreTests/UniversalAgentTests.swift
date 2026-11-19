import XCTest
@testable import MicroCore

final class UniversalAgentTests: XCTestCase {
    func testReportBoundaries() throws {
        for length in [1, 15, 16, 128] {
            let command = String(repeating: "A", count: length)
            let parts = try UniversalAgent.frames(command)
            for hasID in [true, false] {
                var decoder = UniversalAgent.Decoder()
                for (i, part) in parts.enumerated() {
                    XCTAssertEqual(part.count, 20)
                    XCTAssertEqual(part[0...1], [7, 0xa1])
                    let result = try decoder.accept(hasID ? part : Array(part.dropFirst()))
                    XCTAssertEqual(result, i == parts.count - 1 ? command : nil)
                }
            }
        }
    }

    func testRejectsPartialMessageAndRecovers() throws {
        var decoder = UniversalAgent.Decoder()
        let parts = try UniversalAgent.frames(String(repeating: "Z", count: 32))
        XCTAssertNil(try decoder.accept(parts[0]))
        XCTAssertThrowsError(try decoder.accept(parts[2]))
        XCTAssertEqual(try decoder.accept(UniversalAgent.frames("OK")[0]), "OK")
        XCTAssertThrowsError(try UniversalAgent.frames("AMHELLO\n"))
        XCTAssertThrowsError(try UniversalAgent.frames(String(repeating: "a", count: 129)))
    }
}
