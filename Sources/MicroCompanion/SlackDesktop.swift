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
    func url(_ key:String) -> URL? {
        let value = attr(key)
        return (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
    }
    var isMessage: Bool {
        identifier.range(of:#"(message_container|message-container|message-list-item|c-message_kit__background|^message[-_]\d)"#,options:.regularExpression) != nil
    }
    var isThread: Bool {
        ["AXGroup","AXSplitGroup","AXWindow","AXLandmarkRegion"].contains(role) &&
            (identifier.contains("thread-pane") || identifier.contains("thread_view") || ["thread","스레드","스레드 창"].contains(name))
    }
    func named(_ words:[String]) -> Bool { words.contains(where:name.contains) }
}

@MainActor enum SlackDesktop {
    struct Slot {
        let conversation:SlackConversation
        var name:String
        var latest:String
    }
    private(set) static var slots=[Slot]()
    private static var slotsDate = Date.distantPast
    static func clearSlots() { slots=[];slotsDate = .distantPast }
    static func open(_ conversation:SlackConversation) async throws {
        guard let client=NSWorkspace.shared.urlForApplication(withBundleIdentifier:AppProfile.slack.bundleIDs[0]) else {
            throw CompanionError("Mac용 Slack 앱을 찾을 수 없습니다.")
        }
        _ = try await NSWorkspace.shared.open([conversation.deepLink],withApplicationAt:client,configuration:.init())
    }

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
        func unreadArea(_ win:AppNode) -> AppNode? {
            win.descendants({ node in
                guard ["AXGroup","AXLandmarkRegion","AXList","AXScrollArea","AXSplitGroup","AXWebArea"].contains(node.role) else { return false }
                let id=node.identifier
                return id.contains("all_unreads") || id.contains("all-unreads") || id.contains("allunreads") ||
                    ["unreads","all unreads","읽지 않음","읽지 않은 메시지"].contains(node.name)
            },first:true).first
        }
        let initial=try window(app)
        let webArea=initial.descendants({$0.role=="AXWebArea"},first:true).first
        let initialTeam=[webArea?.url("AXURL"),initial.url("AXDocument")].compactMap{$0}.compactMap(SlackConversation.workspace).first
        if Date().timeIntervalSince(slotsDate)<10, slots.indices.contains(slot-1), slots[slot-1].conversation.team == initialTeam {
            try await open(slots[slot-1].conversation)
            return
        }
        clearSlots()
        if unreadArea(initial) == nil { try DesktopShortcut.send("cmd+shift+a",to:.slack) }
        let area=try await waitFor { unreadArea(try window(app)) }
        let win=try window(app)
        let snapshot = try await Task.detached(priority:.userInitiated) { () throws -> [Slot] in
            try Task.checkCancellation()
            let web=area.ancestors.first(where:{$0.role=="AXWebArea"})
            let currentTeam=[web?.url("AXURL"),win.url("AXDocument")].compactMap{$0}.compactMap(SlackConversation.workspace).first ?? initialTeam
            var byID=[SlackConversation:Slot](), order=[SlackConversation]()
            for node in area.descendants({$0.role=="AXLink"}) {
                guard let url=node.url("AXURL"),let id=SlackConversation.parse(url,currentTeam:currentTeam),
                      currentTeam == nil || id.team == currentTeam else { continue }
                // Only navigation headers and message timestamps identify the
                // containing channel. Links posted inside a message may point elsewhere.
                let timestamp=SlackAction.permalink(url)?.timestamp
                let isTime=node.identifier.contains("timestamp") || node.identifier.contains("time_stamp") ||
                    node.name.range(of:#"\d{1,2}:\d{2}"#,options:.regularExpression) != nil
                let parents=node.ancestors.dropFirst()
                let body=parents.contains { $0.identifier.contains("rich_text") || $0.identifier.contains("message-text") || $0.identifier.contains("message__body") }
                guard !body, timestamp == nil ? !parents.contains(where:{$0.isMessage}) : isTime else { continue }
                let title=(node.attr("AXTitle") as? String ?? node.attr("AXDescription") as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
                var entry=byID[id] ?? Slot(conversation:id,name:id.channel,latest:"")
                if byID[id] == nil { order.append(id) }
                if let timestamp { entry.latest=max(entry.latest,timestamp) }
                else if !title.isEmpty { entry.name=title }
                byID[id]=entry
            }
            let ranked=order.enumerated().sorted { lhs,rhs in
                let l=byID[lhs.element]!.latest,r=byID[rhs.element]!.latest
                return l == r ? lhs.offset < rhs.offset : l > r
            }
            return ranked.prefix(6).compactMap { byID[$0.element] }
        }.value
        try Task.checkCancellation()
        slots=snapshot
        slotsDate=Date()
        guard slots.indices.contains(slot-1) else { throw CompanionError("Slack 읽지 않음 화면에서 식별한 대화는 "+String(slots.count)+"개입니다.") }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == AppProfile.slack.bundleIDs[0] else { throw CompanionError("Slack 포커스가 변경되었습니다.") }
        try await open(slots[slot-1].conversation)
    }
    static func perform(_ input:String) async throws {
        guard let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:AppProfile.slack.bundleIDs[0]) else {
            throw CompanionError("Mac용 Slack을 찾을 수 없습니다.")
        }
        let running: NSRunningApplication
        if let opened=NSRunningApplication.runningApplications(withBundleIdentifier:AppProfile.slack.bundleIDs[0]).first {
            running=opened
        } else { running=try await NSWorkspace.shared.openApplication(at:url,configuration:.init()) }
        if !running.isActive { running.activate(options:[]) }
        for _ in 0..<20 where !running.isActive { try await Task.sleep(for:.milliseconds(60)) }
        guard running.isActive else { throw CompanionError("Slack 창을 전면으로 가져올 수 없습니다.") }
        guard AXIsProcessTrusted() else { throw CompanionError("Slack 제어에는 macOS 손쉬운 사용 권한이 필요합니다.") }
        let app=AppNode(element:AXUIElementCreateApplication(running.processIdentifier))
        AXUIElementSetMessagingTimeout(app.element,0.4)
        AXUIElementSetAttributeValue(app.element,"AXManualAccessibility" as CFString,kCFBooleanTrue)
        if let chord=["JOY_LEFT":"cmd+[","JOY_RIGHT":"cmd+]","JOY_UP":"alt+shift+up","JOY_DOWN":"alt+shift+down","K12":"cmd+n"][input] {
            try DesktopShortcut.send(chord,to:.slack); return
        }
        if input.hasPrefix("K"), let slot=Int(input.dropFirst()), (1...6).contains(slot) {
            try await openUnread(slot,app:app); return
        }
        let focused=app.node("AXFocusedUIElement")
        switch input {
        case "K07","K08":
            if focused?.ancestors.contains(where:{ $0.isMessage }) == true {
                try DesktopShortcut.send(input=="K07" ? "up":"down",to:.slack)
            } else {
                let root=try focused?.ancestors.first(where:{ $0.isThread }) ?? window(app)
                guard let last=(input=="K07" ? root.descendants({$0.isMessage}).last : root.descendants({$0.isMessage},first:true).first),
                      AXUIElementSetAttributeValue(last.element,kAXFocusedAttribute as CFString,kCFBooleanTrue) == .success else {
                    throw CompanionError("메시지 목록에 포커스를 둘 수 없습니다.")
                }
            }
        case "K09":
            guard let message=focused?.ancestors.first(where:{ $0.isMessage }),
                  let replies=message.descendants({ ["AXButton","AXLink"].contains($0.role) &&
                    $0.name.range(of:#"(\d+[\s,]*(repl(y|ies)|개의? 답글|답글)|답글\s*\d+)"#,options:.regularExpression) != nil },first:true).first else { throw CompanionError("포커스된 메시지에 열 수 있는 답글이 없습니다.") }
            try replies.press()
        case "K10":
            guard let thread=focused?.ancestors.first(where:{ $0.isThread }),
                  let close=thread.descendants({ $0.role=="AXButton" && $0.named(["close","닫기"]) },first:true).first else { throw CompanionError("포커스된 스레드의 닫기 버튼을 찾을 수 없습니다.") }
            try close.press()
        case "K11":
            try DesktopShortcut.send("cmd+shift+o",to:.slack)
            let mini=try await waitFor {
                let w=try window(app)
                if w.named(["slackbot","슬랙봇"]) { return w }
                return w.descendants({ ["AXDialog","AXSheet","AXGroup"].contains($0.role) && ($0.identifier.contains("slackbot_mini") || $0.identifier.contains("slackbot-mini")) },first:true).first
            }
            if let fresh=mini.descendants({ $0.role=="AXButton" && $0.named(["new conversation","new chat","새 대화","새 채팅"]) },first:true).first { try fresh.press() }
            else if mini.descendants({ $0.role=="AXTextArea" && ($0.attr("AXValue") as? String ?? "").isEmpty },first:true).isEmpty {
                throw CompanionError("Slackbot 새 질문 입력란을 찾을 수 없습니다.")
            }
        case "K13":
            guard let editor=focused?.ancestors.first(where:{ $0.role=="AXTextArea" || $0.identifier.contains("ql-editor") }),
                  let send=editor.ancestors.lazy.filter({ $0.identifier.contains("msg_input") || $0.identifier.contains("message_input") || $0.identifier.contains("message-input") || $0.identifier.contains("composer") }).compactMap({ composer in
                    composer.descendants({ $0.role=="AXButton" && ($0.name=="send" || $0.named(["send now","send message","send a message","메시지 보내기","지금 보내기","보내기"])) && ($0.attr("AXEnabled") as? Bool != false) && !$0.named(["schedule","later","예약","나중에"]) },first:true).first
                  }).first else { throw CompanionError("보낼 메시지의 입력란에 포커스를 두세요.") }
            try send.press()
        default: break
        }
    }
}
