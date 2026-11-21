import AppKit
import CoreAudio
import MicroCore

@MainActor enum T3Controls {
    static func visibleRoute() -> URL? { try? Context().route }

    private struct Context {
        let app: NSRunningApplication
        let root: AppNode
        let web: AppNode
        var route: URL? { (web.attr("AXURL") as? URL) ?? (web.attr("AXURL") as? String).flatMap(URL.init(string:)) }

        init() throws {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier:AppProfile.t3.bundleIDs[0]).first else {
                throw CompanionError("T3 Code를 먼저 열어 주세요.")
            }
            self.app = app
            let root = AppNode(element:AXUIElementCreateApplication(app.processIdentifier))
            self.root = root
            AXUIElementSetAttributeValue(root.element,"AXManualAccessibility" as CFString,kCFBooleanTrue)
            guard let web = root.node("AXFocusedWindow")?.descendants({ $0.role == "AXWebArea" },first:true).first else {
                throw CompanionError("T3 창과 손쉬운 사용 권한을 확인하세요.")
            }
            self.web = web
        }

        // Do not operate on controls inside an embedded browser preview.
        func nodes(_ match:(AppNode)->Bool) -> [AppNode] {
            var stack=Array(web.children.reversed()), result=[AppNode]()
            while let node=stack.popLast() {
                if node.role == "AXWebArea" { continue }
                if match(node) { result.append(node) }
                stack.append(contentsOf:node.children.reversed())
            }
            return result
        }
        func buttons(_ labels:[String]) -> [AppNode] {
            nodes { $0.role == "AXButton" && $0.attr("AXEnabled") as? Bool != false && labels.contains(ClaudeControls.label($0)) }
        }
        var endButton: AppNode? {
            nodes { $0.role == "AXButton" && ClaudeControls.label($0).hasPrefix("Scroll to end") }.first
        }
        func focusComposer() throws {
            let editors=nodes { $0.role == "AXTextArea" && $0.identifier.contains("composer-tiptap") }
            guard editors.count == 1,
                  AXUIElementSetAttributeValue(editors[0].element,kAXFocusedAttribute as CFString,kCFBooleanTrue) == .success,
                  let focus=root.node("AXFocusedUIElement"), CFEqual(focus.element,editors[0].element) else {
                throw CompanionError("T3 메시지 입력란을 선택할 수 없습니다.")
            }
        }
    }

    private static func chord(_ command:String, default fallback:String) throws -> String {
        let file=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".t3/userdata/keybindings.json")
        guard FileManager.default.fileExists(atPath:file.path) else { return fallback }
        struct Binding: Decodable { let command,key:String }
        let entries=try JSONDecoder().decode([Binding].self,from:Data(contentsOf:file))
        guard let entry=entries.first(where:{ $0.command == command }) else { throw CompanionError("T3 단축키 설정을 확인하세요 · "+command) }
        let aliases=["mod":"cmd","meta":"cmd","option":"alt","arrowdown":"down","arrowup":"up","arrowleft":"left","arrowright":"right"]
        let value=entry.key.lowercased().components(separatedBy:"+").map { aliases[$0] ?? $0 }.joined(separator:"+")
        guard DesktopShortcut.valid(value) else { throw CompanionError("지원하지 않는 T3 단축키입니다 · "+entry.key) }
        return value
    }

    struct Dictation {
        let root:AppNode
        let editor:AppNode
        let started = ProcessInfo.processInfo.systemUptime

        func finish() throws {
            // Escape sent before DictationIM opens the microphone is consumed by Electron.
            // Poll only during startup. Read the system capture state, never the audio.
            let now = ProcessInfo.processInfo
            if #available(macOS 14.2, *) {
                while now.systemUptime < started + 1.5 && !Self.speechInputActive() { Thread.sleep(forTimeInterval:0.025) }
            } else if now.systemUptime < started + 0.7 {
                Thread.sleep(forTimeInterval:started + 0.7 - now.systemUptime)
            }
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == AppProfile.t3.bundleIDs.first,
                  let focus = root.node("AXFocusedUIElement"), CFEqual(focus.element,editor.element) else {
                throw CompanionError("T3 작성창의 포커스가 바뀌었습니다. 받아쓰기 상태를 확인하세요.")
            }
            // Dictation runs in the system input method, before events reach T3.
            guard let down = CGEvent(keyboardEventSource:nil,virtualKey:53,keyDown:true),
                  let up = CGEvent(keyboardEventSource:nil,virtualKey:53,keyDown:false) else {
                throw CompanionError("받아쓰기 종료 키를 만들 수 없습니다.")
            }
            down.flags = []
            up.flags = []
            down.post(tap:.cghidEventTap)
            up.post(tap:.cghidEventTap)
        }

        @available(macOS 14.2, *)
        private static func speechInputActive() -> Bool {
            func address(_ selector:AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
                .init(mSelector:selector,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
            }
            var list = address(kAudioHardwarePropertyProcessObjectList), size:UInt32 = 0
            guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),&list,0,nil,&size) == noErr, size > 0 else { return false }
            var ids = [AudioObjectID](repeating:0,count:Int(size)/MemoryLayout<AudioObjectID>.size)
            guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&list,0,nil,&size,&ids) == noErr else { return false }
            return ids.contains { id in
                var active:UInt32 = 0, bytes = UInt32(MemoryLayout<UInt32>.size)
                var input = address(kAudioProcessPropertyIsRunningInput)
                guard AudioObjectGetPropertyData(id,&input,0,nil,&bytes,&active) == noErr, active != 0 else { return false }
                var pid:pid_t = 0, prop = address(kAudioProcessPropertyPID)
                guard AudioObjectGetPropertyData(id,&prop,0,nil,&bytes,&pid) == noErr else { return false }
                var name = [CChar](repeating:0,count:256)
                return proc_name(pid,&name,UInt32(name.count)) > 0 && String(cString:name) == "corespeechd"
            }
        }
    }

    static func startDictation() throws -> Dictation {
        let ctx = try Context()
        ctx.app.activate(options:[])
        try ctx.focusComposer()
        guard let editor = ctx.root.node("AXFocusedUIElement") else { throw CompanionError("T3 작성창을 확인하세요.") }
        let labels = ["Start Dictation…","Start Dictation","받아쓰기 시작…","받아쓰기 시작"]
        let items = ctx.root.node("AXMenuBar")?.descendants {
            $0.role == "AXMenuItem" && labels.contains(ClaudeControls.label($0)) && $0.attr("AXEnabled") as? Bool != false
        } ?? []
        guard items.count == 1 else { throw CompanionError("macOS 키보드 설정에서 받아쓰기를 확인하세요.") }
        try items[0].press()
        return Dictation(root:ctx.root,editor:editor)
    }

    static func perform(_ action:String, stillActive:()->Bool) async throws {
        if let command = AppProfile.t3Commands.first(where:{ action == "agent.t3."+$0.id }) {
            let ctx = try Context()
            try ctx.focusComposer()
            try DesktopShortcut.send(chord(command.id,default:command.chord),to:.t3)
            return
        }
        switch action {
        case "agent.terminal","agent.rightPanel":
            let terminal=action == "agent.terminal"
            let label=terminal ? "Toggle terminal drawer" : "Toggle right panel"
            let toggles=try Context().nodes { ["AXCheckBox","AXButton"].contains($0.role) && ClaudeControls.label($0) == label }
            if !toggles.isEmpty {
                guard toggles.count == 1,toggles[0].attr("AXEnabled") as? Bool != false else { throw CompanionError("현재 대화에서 이 패널을 열 수 없습니다.") }
                try toggles[0].press()
                return
            }
            try DesktopShortcut.send(chord(terminal ? "terminal.toggle" : "rightPanel.toggle",default:terminal ? "cmd+j" : "cmd+alt+b"),to:.t3)
        case "agent.nextPending":
            let pending=try await Task.detached { try DesktopSessions.read(.t3,pendingT3Only:true) }.value
            guard stillActive() else { return }
            guard !pending.isEmpty else { throw CompanionError("입력을 기다리는 T3 세션이 없습니다.") }
            let route=try Context().route
            let parts=(route?.fragment?.components(separatedBy:"?").first ?? route?.path ?? "").split(separator:"/").suffix(2)
            let index=pending.firstIndex { $0.url.pathComponents.suffix(2).elementsEqual(parts.map(String.init)) }
            try await DesktopSessions.open(pending[index.map { ($0+1)%pending.count } ?? 0],profile:.t3)
        case "agent.newChat":
            let ctx=try Context()
            let newButtons=ctx.nodes { $0.role == "AXButton" && ClaudeControls.label($0).hasPrefix("New thread in ") && $0.attr("AXEnabled") as? Bool != false }
            if newButtons.count == 1 { try newButtons[0].press(); return }
            try ctx.focusComposer()
            try DesktopShortcut.send(chord("chat.new",default:"cmd+shift+o"),to:.t3)
        case "agent.approve","agent.decline":
            let ctx=try Context()
            let groups=["Command approval","File change approval","File read approval","App permission approval","App access approval"]
            let approve=action == "agent.approve"
            let candidates=ctx.buttons(approve ? ["Approve","Allow","Allow once","Yes, proceed"] : ["Decline","Deny","Reject"]).filter { node in
                let ancestors=node.ancestors
                return ancestors.contains { $0.role == "AXGroup" && groups.contains(ClaudeControls.label($0)) } &&
                       !ancestors.contains { ClaudeControls.label($0).hasPrefix("Approval from ") }
            }
            guard candidates.count == 1 else { throw CompanionError("현재 세션에서 처리할 승인 요청 한 건을 확인할 수 없습니다.") }
            try candidates[0].press()
        case "agent.fork":
            var ctx=try Context()
            if let scroll=ctx.endButton {
                let original=ctx.route
                try scroll.press()
                for _ in 0..<12 {
                    try await Task.sleep(nanoseconds:100_000_000)
                    guard stillActive() else { return }
                    ctx=try Context()
                    guard let original,ctx.route == original else { throw CompanionError("T3 세션이 변경됐습니다.") }
                    if ctx.endButton == nil { break }
                }
                guard ctx.endButton == nil else { throw CompanionError("최근 응답으로 이동한 뒤 다시 눌러 주세요.") }
            }
            guard let fork=ctx.buttons(["Fork from this response"]).last else { throw CompanionError("포크할 수 있는 응답이 없습니다.") }
            try fork.press()
        case "agent.settle":
            let ctx = try Context()
            guard let route = ctx.route else { throw CompanionError("현재 T3 대화를 확인할 수 없습니다.") }
            guard try DesktopSessions.t3NeedsSettlement(route:route) else { return }
            try ctx.focusComposer()
            guard stillActive(), ctx.route == route else { throw CompanionError("T3 세션이 변경됐습니다.") }
            try DesktopShortcut.send(chord("thread.settle",default:"cmd+shift+s"),to:.t3)
        case "agent.stop","agent.resume":
            let buttons = try Context().buttons([action == "agent.stop" ? "Stop generation" : "Resume thread"])
            guard buttons.count == 1 else { throw CompanionError("현재 대화에서 해당 동작을 사용할 수 없습니다.") }
            try buttons[0].press()
        case "agent.submit":
            let buttons=try Context().buttons(ComposerAvailability.t3SendLabels)
            guard buttons.count == 1 else { throw CompanionError("보낼 수 있는 T3 메시지가 없습니다.") }
            try buttons[0].press()
        default: throw CompanionError("알 수 없는 T3 기능입니다.")
        }
    }
}
