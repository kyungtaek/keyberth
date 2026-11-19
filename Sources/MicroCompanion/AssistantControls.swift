import AppKit
import MicroCore

enum ClaudeControls {
    static func window(_ profile: AppProfile) throws -> AppNode {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier:profile.bundleIDs[0]).first,
              let window = AppNode(element:AXUIElementCreateApplication(app.processIdentifier)).node("AXFocusedWindow")
        else { throw CompanionError(profile.title+" 창과 손쉬운 사용 권한을 확인하세요.") }
        return window
    }
    static func label(_ node: AppNode) -> String {
        for key in ["AXTitle","AXDescription","AXHelp","AXValue"] {
            if let text = node.attr(key) as? String, !text.isEmpty { return text }
        }
        return ""
    }
    private static func recentLinks() throws -> [(AppNode, DesktopSession)] {
        let win = try window(.claude)
        let names = ["recents","recent","recent chats","recent conversations","최근","최근 대화","최근 항목"]
        var regions = win.descendants { node in
            ["AXGroup","AXList","AXLandmarkRegion","AXNavigation"].contains(node.role) && names.contains(label(node).lowercased())
        }
        if regions.isEmpty {
            for heading in win.descendants({ ["AXHeading","AXStaticText"].contains($0.role) && names.contains(label($0).lowercased()) }) {
                for parent in heading.ancestors.dropFirst().prefix(4) {
                    if let list = parent.children.first(where:{ $0.role == "AXList" }) { regions.append(list); break }
                }
            }
        }
        var seen = Set<URL>(), result = [(AppNode, DesktopSession)]()
        for region in regions {
            for node in region.descendants({ $0.role == "AXLink" }) {
                guard let url = (node.attr("AXURL") as? URL) ?? (node.attr("AXURL") as? String).flatMap(URL.init(string:)),
                      url.host == "claude.ai", url.pathComponents.count == 3, url.pathComponents[1] == "chat",
                      UUID(uuidString:url.lastPathComponent) != nil, seen.insert(url).inserted else { continue }
                let status = node.attr("AXValueDescription") as? String ?? ""
                let states: [String:SessionLight] = ["running":.running,"working":.running,"needs input":.attention,"completed":.done,"실행 중":.running,"입력 대기":.attention,"완료":.done]
                result.append((node,DesktopSession(url:url,title:label(node),light:states[status.lowercased()] ?? .unknown)))
                if result.count == 6 { return result }
            }
        }
        return result
    }
    static func sessions() throws -> [DesktopSession] { try recentLinks().map { $0.1 } }
    static func open(_ url: URL) throws {
        guard let node = try recentLinks().first(where:{ $0.1.url == url })?.0 else { throw CompanionError("최근 대화가 변경되었습니다.") }
        NSRunningApplication.runningApplications(withBundleIdentifier:AppProfile.claude.bundleIDs[0]).first?.activate(options:[])
        try node.press()
    }
    static func press(_ labels: [String], in profile: AppProfile, approval: Bool = false) throws {
        let root = try window(profile)
        let matches = root.descendants { node in
            guard ["AXButton","AXMenuItem","AXPopUpButton","AXRadioButton"].contains(node.role),
                  (labels.contains(label(node).lowercased()) ||
                    (labels.contains("model selector") && label(node).range(of:#"^(Claude )?(Sonnet|Haiku|Opus) [0-9]+([.][0-9]+)*$"#,options:[.regularExpression,.caseInsensitive]) != nil)), node.attr("AXEnabled") as? Bool != false else { return false }
            if !approval { return true }
            return node.ancestors.contains { ancestor in
                let subrole = ancestor.attr("AXSubrole") as? String ?? ""
                return subrole.contains("Dialog") || ["permission","approval","승인 요청","권한 요청"].contains(where:ancestor.identifier.contains)
            }
        }
        guard matches.count == 1 else { throw CompanionError(profile.title+"에서 ‘"+labels[0]+"’ 컨트롤을 확인할 수 없습니다.") }
        try matches[0].press()
    }
}

enum AssistantControls {
    // Read the user's app-level shortcut, including explicit unbinding.
    static func codexChord(_ command:String, fallback:String?) throws -> String {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/keybindings.json")
        if FileManager.default.fileExists(atPath:url.path) {
            let config = try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [[String:Any]]
            let entries = config?.filter { $0["command"] as? String == command } ?? []
            let aliases = ["command":"cmd","cmdorctrl":"cmd","commandorcontrol":"cmd","option":"alt","control":"ctrl","return":"enter"]
            for entry in entries {
                guard let key = entry["key"] as? String else { continue }
                let chord = key.lowercased().components(separatedBy:"+").map { aliases[$0] ?? $0 }.joined(separator:"+")
                if DesktopShortcut.valid(chord) { return chord }
            }
            if !entries.isEmpty { throw CompanionError("Codex 단축키 설정을 확인하세요 · "+command) }
        }
        guard let fallback else { throw CompanionError("Codex에서 단축키를 지정하세요 · "+command) }
        return fallback
    }

    @MainActor static func perform(_ action:String, in profile:AppProfile) throws {
        let codex = profile == .codex
        switch action {
        case "agent.approve","agent.decline":
            if codex, let chord = try? codexChord(action == "agent.approve" ? "approval.approve" : "approval.decline", fallback:nil),
               chord.contains("+") {
                try DesktopShortcut.send(chord,to:profile)
                return
            }
            try ClaudeControls.press(action == "agent.approve" ? ["allow once","allow this time","approve once","이번만 허용","이번 요청 승인","한 번 허용"] :
                                        ["decline","deny","거절","거부"],in:profile,approval:true)
        case "agent.newChat":
            let chord = codex ? try codexChord("newTask",fallback:"cmd+n") : "cmd+n"
            try DesktopShortcut.send(chord,to:profile)
        case "agent.submit": try DesktopShortcut.send("enter",to:profile)
        case "agent.back","agent.forward": try DesktopShortcut.send(action == "agent.back" ? "cmd+[" : "cmd+]",to:profile)
        case "agent.fast","agent.fork","agent.plan","agent.sidebar","agent.mic":
            if codex {
                let commands = ["agent.fast":"composer.toggleFastMode","agent.fork":"forkThread","agent.plan":"composer.togglePlanMode","agent.sidebar":"toggleSidebar","agent.mic":"composer.toggleDictation"]
                let defaults = ["agent.sidebar":"cmd+b","agent.mic":"cmd+shift+d"]
                try DesktopShortcut.send(codexChord(commands[action]!,fallback:defaults[action]),to:profile)
            } else {
                let labels = ["agent.fast":["select model","choose model","model selector","모델 선택"],
                              "agent.fork":["branch conversation","branch from here","fork conversation","대화 분기","여기에서 분기"],
                              "agent.plan":["plan mode","계획 모드"],"agent.sidebar":["toggle sidebar","open sidebar","close sidebar","사이드바 열기","사이드바 닫기"],
                              "agent.mic":["start dictation","dictate","받아쓰기 시작","받아쓰기"]]
                try ClaudeControls.press(labels[action]!,in:profile)
            }
        default: throw CompanionError("지원하지 않는 기능입니다.")
        }
    }
}
