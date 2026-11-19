import AppKit
import ApplicationServices
import MicroCore

// Slack's Electron accessibility tree is scoped to the focused window and UI region.
// Never infer channel or thread actions from matching text in a message body.
struct AppNode {
    let element: AXUIElement
    func attr(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element,name as CFString,&value) == .success ? value : nil
    }
    func node(_ name: String) -> Self? {
        guard let value=attr(name), CFGetTypeID(value)==AXUIElementGetTypeID() else { return nil }
        return Self(element:value as! AXUIElement)
    }
    var role: String { attr("AXRole") as? String ?? "" }
    var name: String { ([attr("AXTitle"),attr("AXDescription"),attr("AXHelp")].compactMap { $0 as? String }).joined(separator:" ").lowercased() }
    var identifier: String { ([attr("AXDOMIdentifier"),attr("AXIdentifier")].compactMap { $0 as? String } + (attr("AXDOMClassList") as? [String] ?? [])).joined(separator:" ").lowercased() }
    var children: [Self] { (attr("AXChildren") as? [AXUIElement] ?? []).map(Self.init) }
    var ancestors: [Self] {
        var result=[self]
        for _ in 0..<35 { guard let parent=result.last?.node("AXParent") else { break }; result.append(parent) }
        return result
    }
    func descendants(_ predicate:(Self)->Bool, first:Bool=false) -> [Self] {
        var stack=[self], result=[Self](), visited=0
        while let item=stack.popLast(), visited<4000 {
            visited+=1
            if predicate(item) { result.append(item); if first { break } }
            stack.append(contentsOf:item.children.reversed())
        }
        return result
    }
    func press() throws {
        guard AXUIElementPerformAction(element,kAXPressAction as CFString) == .success else { throw CompanionError("앱에서 항목을 실행할 수 없습니다.") }
    }
    var isMessage: Bool {
        identifier.range(of:#"(message_container|message-container|message-list-item|^message[-_]\d)"#,options:.regularExpression) != nil
    }
    var isThread: Bool {
        ["AXGroup","AXSplitGroup","AXWindow","AXLandmarkRegion"].contains(role) &&
            (identifier.contains("thread-pane") || identifier.contains("thread_view") || ["thread","스레드","스레드 창"].contains(name))
    }
    func named(_ words:[String]) -> Bool { words.contains(where:name.contains) }
}

enum SlackDesktop {
    private static func window(_ app: AppNode) throws -> AppNode {
        guard let win=app.node("AXFocusedWindow") else { throw CompanionError("Slack 창을 열고 손쉬운 사용 권한을 확인하세요.") }
        return win
    }
    private static func waitFor(_ predicate:()throws -> AppNode?) async throws -> AppNode {
        for _ in 0..<12 {
            if let node=try predicate() { return node }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        throw CompanionError("Slack에서 해당 화면을 찾을 수 없습니다.")
    }
    private static func openUnread(_ slot:Int, app:AppNode) async throws {
        try await DesktopShortcut.send("cmd+shift+a",to:.slack)
        let area=try await waitFor {
            try window(app).descendants({ node in
                ["AXGroup","AXLandmarkRegion","AXList","AXScrollArea","AXSplitGroup"].contains(node.role) &&
                (node.identifier.contains("all_unreads") || node.identifier.contains("all-unreads") || ["unreads","읽지 않음","읽지 않은 메시지"].contains(node.name))
            }, first:true).first
        }
        // Slack permalink timestamps sort exactly as decimal digit strings. Each
        // conversation contributes only its newest unread message to the six slots.
        var newest=[String:(String,AppNode)]()
        for link in area.descendants({ $0.role == "AXLink" }) {
            guard let url=(link.attr("AXURL") as? URL) ?? (link.attr("AXURL") as? String).flatMap(URL.init(string:)),
                  let item=SlackAction.permalink(url) else { continue }
            if newest[item.channel].map({ $0.0 >= item.timestamp }) == true { continue }
            newest[item.channel]=(item.timestamp,link)
        }
        let ranked=newest.sorted { $0.value.0 == $1.value.0 ? $0.key < $1.key : $0.value.0 > $1.value.0 }
        guard ranked.indices.contains(slot-1) else { throw CompanionError("읽지 않음 화면에서 \(slot)번째 대화를 찾을 수 없습니다.") }
        try ranked[slot-1].value.1.press()
    }
    static func perform(_ input:String) async throws {
        guard let running=NSRunningApplication.runningApplications(withBundleIdentifier:AppProfile.slack.bundleIDs[0]).first else {
            throw CompanionError("Slack 데스크톱 앱을 먼저 열어 주세요.")
        }
        let app=AppNode(element:AXUIElementCreateApplication(running.processIdentifier))
        AXUIElementSetMessagingTimeout(app.element,0.4)
        if let chord=["JOY_LEFT":"cmd+[","JOY_RIGHT":"cmd+]","JOY_UP":"alt+shift+up","JOY_DOWN":"alt+shift+down","K12":"cmd+n"][input] {
            try await DesktopShortcut.send(chord,to:.slack); return
        }
        guard AXIsProcessTrusted() else { throw CompanionError("Slack 제어에는 macOS 손쉬운 사용 권한이 필요합니다.") }
        AXUIElementSetAttributeValue(app.element,"AXManualAccessibility" as CFString,kCFBooleanTrue)
        if input.hasPrefix("K"), let slot=Int(input.dropFirst()), (1...6).contains(slot) {
            try await openUnread(slot,app:app); return
        }
        let focused=app.node("AXFocusedUIElement")
        switch input {
        case "K07","K08":
            if focused?.ancestors.contains(where:{ $0.isMessage }) == true {
                try await DesktopShortcut.send(input=="K07" ? "up":"down",to:.slack)
            } else {
                let root=try focused?.ancestors.first(where:{ $0.isThread }) ?? window(app)
                guard let last=root.descendants({$0.isMessage}).last,
                      AXUIElementSetAttributeValue(last.element,kAXFocusedAttribute as CFString,kCFBooleanTrue) == .success else {
                    throw CompanionError("메시지 목록에 포커스를 둘 수 없습니다.")
                }
            }
        case "K09":
            guard let message=focused?.ancestors.first(where:{ $0.isMessage }),
                  let replies=message.descendants({ ["AXButton","AXLink"].contains($0.role) &&
                    $0.name.range(of:#"(\d+[\s,]*(repl(y|ies)|개의? 답글|답글)|답글\s*\d+)"#,options:.regularExpression) != nil },first:true).first else { return }
            try replies.press()
        case "K10":
            guard let thread=focused?.ancestors.first(where:{ $0.isThread }),
                  let close=thread.descendants({ $0.role=="AXButton" && $0.named(["close","닫기"]) },first:true).first else { return }
            try close.press()
        case "K11":
            try await DesktopShortcut.send("cmd+shift+o",to:.slack)
            let mini=try await waitFor { let w=try window(app); return w.named(["slackbot","슬랙봇"]) ? w:nil }
            if let fresh=mini.descendants({ $0.role=="AXButton" && $0.named(["new conversation","new chat","새 대화","새 채팅"]) },first:true).first { try fresh.press() }
            else if mini.descendants({ $0.role=="AXTextArea" && ($0.attr("AXValue") as? String ?? "").isEmpty },first:true).isEmpty {
                throw CompanionError("Slackbot 새 질문 입력란을 찾을 수 없습니다.")
            }
        case "K13":
            guard let editor=focused?.ancestors.first(where:{ $0.role=="AXTextArea" || $0.identifier.contains("ql-editor") }),
                  let send=editor.ancestors.lazy.filter({ $0.identifier.contains("msg_input") || $0.identifier.contains("message_input") || $0.identifier.contains("message-input") || $0.identifier.contains("composer") }).compactMap({ composer in
                    composer.descendants({ $0.role=="AXButton" && $0.named(["send now","send message","메시지 보내기","지금 보내기"]) && !$0.named(["schedule","예약"]) },first:true).first
                  }).first else { throw CompanionError("보낼 메시지의 입력란에 포커스를 두세요.") }
            try send.press()
        default: break
        }
    }
}
