import XCTest
@testable import MicroCore

final class AppProfileTests: XCTestCase {
    func testEncoderCycleWrapsInBothDirections() {
        var profile = AppProfile.cmux
        var seen: [AppProfile] = []
        for _ in AppProfile.allCases {
            seen.append(profile)
            let next = profile.advanced(by: 1)
            XCTAssertEqual(next.advanced(by: -1), profile)
            profile = next
        }
        XCTAssertEqual(seen, [.cmux, .slack, .obsidian, .t3, .claude, .codex])
        XCTAssertEqual(profile, .cmux)
        XCTAssertNil(AppProfile.fixedAction("TOUCH"))
    }

    func testSlackActionCoverageAndUnreadPermalinks() {
        XCTAssertEqual(SlackAction.inputs.count, 17)
        XCTAssertEqual(SlackAction.inputs.count, SlackAction.labels.count)
        for input in SlackAction.inputs {
            XCTAssertEqual(SlackAction.input(AppProfile.slack.defaultBinding(input)), input)
        }
        XCTAssertNil(SlackAction.input("slack.ENC_PRESS"))
        let url = URL(string:"https://example.slack.com/archives/C123/p1712345678123456")!
        XCTAssertEqual(SlackAction.permalink(url)?.channel, "C123")
        XCTAssertEqual(SlackAction.permalink(url)?.timestamp, "1712345678123456")
        XCTAssertNil(SlackAction.permalink(URL(string:"https://example.org/archives/C123/p1712345678123456")!))
        XCTAssertNil(SlackAction.permalink(URL(string:"https://example.slack.com/archives/C123")!))
    }
    func testAssistantLayoutsMatchMicroPositions() {
        for profile in [AppProfile.t3,.claude,.codex] {
            for slot in 1...6 {
                let value = profile.defaultBinding(String(format:"K%02d",slot))
                XCTAssertEqual(value,"recent.\(slot)")
                XCTAssertNotNil(profile.agentActions[value])
            }
        }
        for profile in [AppProfile.claude,.codex] {
            let actions = (7...13).map { profile.defaultBinding(String(format:"K%02d",$0)) }
            XCTAssertEqual(actions,["agent.fast","agent.approve","agent.decline","agent.fork","agent.mic","agent.newChat","agent.submit"])
            XCTAssertTrue(actions.allSatisfy { profile.agentActions[$0] != nil })
            XCTAssertEqual(profile.defaultBinding("JOY_UP"),"agent.plan")
        }
    }

    func testBindingsAndApplicationIdentity() {
        let ids = AppProfile.allCases.flatMap(\.bundleIDs)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(AppProfile.cmux.defaultBinding("K01"), "K01")
        XCTAssertEqual(AppProfile.slack.defaultBinding("K01"), "slack.K01")
        XCTAssertEqual(AppProfile.obsidian.defaultBinding("K01"), "cmd+o")
        XCTAssertTrue(["ENC_CW","ENC_CCW","ENC_PRESS"].allSatisfy { AppProfile.fixedAction($0) != nil })
    }
}
