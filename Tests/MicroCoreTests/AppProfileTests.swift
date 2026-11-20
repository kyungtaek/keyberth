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
        XCTAssertEqual(seen, [.cmux,.t3,.codex,.claude,.claudeCode])
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
    func testSlackChannelIdentityAcrossWorkspaces() throws {
        let channel=try XCTUnwrap(SlackConversation(team:"T123",channel:"C456"))
        func parse(_ value:String, _ team:String?=nil)->SlackConversation? {
            SlackConversation.parse(URL(string:value)!,currentTeam:team)
        }
        XCTAssertEqual(parse("https://app.slack.com/client/T123/C456"),channel)
        XCTAssertEqual(parse("https://acme.slack.com/archives/C456/p1234567890123456","T123"),channel)
        XCTAssertNil(parse("https://acme.slack.com/archives/C456"))
        XCTAssertNil(parse("https://app.slack.com.example.org/client/T123/C456"))
        XCTAssertNotEqual(parse("https://app.slack.com/client/T567/C456"),channel)
        XCTAssertEqual(parse(channel.deepLink.absoluteString),channel)
    }
    func testAssistantLayoutsMatchMicroPositions() {
        for profile in [AppProfile.t3,.claudeCode,.codex] {
            for slot in 1...6 {
                XCTAssertEqual(profile.defaultBinding(String(format:"K%02d", slot)), "recent."+String(slot))
            }
        }
        let expected: [AppProfile:[String]] = [

            .claude:["cmd+b","ctrl+cmd+f","cmd+=","cmd+-","ctrl+shift+tab","ctrl+tab","escape","cmd+a","backspace","cmd+z","cmd+d","cmd+n","enter"]
        ]
        for (profile, keys) in expected {
            XCTAssertEqual((1...13).map { profile.defaultBinding(String(format:"K%02d",$0)) }, keys)
            for direction in ["up","down","left","right"] {
                XCTAssertEqual(profile.defaultBinding("JOY_"+direction.uppercased()),direction)
            }
        }
        XCTAssertEqual((7...13).map {AppProfile.codex.defaultBinding(String(format:"K%02d",$0))},["agent.dots","agent.approve","agent.decline","agent.fork","agent.mic","agent.newChat","agent.submit"])
        XCTAssertEqual(AppProfile(rawValue:"app.org.example.Editor")?.bundleIDs,["org.example.Editor"])
        for index in 7...13 {
            let key=String(format:"K%02d",index)
            XCTAssertEqual(AppProfile.claudeCode.defaultBinding(key),AppProfile.claude.defaultBinding(key))
        }
    }

    func testT3PanelAndConversationBindings() {
        let inputs = ["JOY_DOWN","JOY_RIGHT","K07","K08","K09","K10","K11","K12","K13"]
        let actions = inputs.map { AppProfile.t3.defaultBinding($0) }
        XCTAssertEqual(actions, ["agent.terminal","agent.rightPanel","agent.nextPending","agent.approve","agent.decline","agent.fork","agent.dictate","agent.newChat","agent.submit"])
        XCTAssertTrue(actions.allSatisfy { AppProfile.t3.agentActions[$0] != nil })
        XCTAssertEqual(AppProfile.t3.defaultBinding("JOY_UP"),"up")
        XCTAssertEqual(AppProfile.t3.defaultBinding("JOY_LEFT"),"left")
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
