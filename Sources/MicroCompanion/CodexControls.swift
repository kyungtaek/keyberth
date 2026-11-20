import AppKit
import MicroCore

enum CodexControls {
    static func window() throws -> AppNode {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: AppProfile.codex.bundleIDs[0]).first else {
            throw CompanionError("Codex Desktop을 먼저 열어 주세요.")
        }
        let root = AppNode(element: AXUIElementCreateApplication(app.processIdentifier))
        AXUIElementSetAttributeValue(root.element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard let window = root.node("AXFocusedWindow") else { throw CompanionError("Codex 창과 손쉬운 사용 권한을 확인하세요.") }
        return window
    }

    private static func control(_ root: AppNode, role: String, labels: [String]) -> AppNode? {
        let matches = root.descendants { node in
            node.role == role && labels.contains(ClaudeControls.label(node).lowercased()) && node.attr("AXEnabled") as? Bool != false
        }
        if matches.count == 1 { return matches[0] }
        // A pending question can expose another dictation button above the primary composer.
        let composer = matches.filter { $0.ancestors.contains { $0.identifier.contains("composerlayoutbody-") } }
        return composer.count == 1 ? composer[0] : nil
    }

    // Chromium can acknowledge AXPress without dispatching a pointer event.
    // Only click a verified, visible control under the pointer coordinates.
    private static func click(_ button:AppNode) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == AppProfile.codex.bundleIDs.first,
              let p = button.attr("AXPosition"), let s = button.attr("AXSize"),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return false }
        var position = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue,.cgPoint,&position), AXValueGetValue(s as! AXValue,.cgSize,&size) else { return false }
        let point = CGPoint(x:position.x + size.width/2,y:position.y + size.height/2)
        var hit:AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),Float(point.x),Float(point.y),&hit) == .success,
              let hit, AppNode(element:hit).ancestors.contains(where:{ CFEqual($0.element,button.element) }),
              let down = CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:point,mouseButton:.left),
              let up = CGEvent(mouseEventSource:nil,mouseType:.leftMouseUp,mouseCursorPosition:point,mouseButton:.left) else { return false }
        down.post(tap:.cghidEventTap)
        up.post(tap:.cghidEventTap)
        return true
    }

    struct Dictation {
        let window: AppNode
        let stopChord: String
    }

    @MainActor static func startDictation() throws -> Dictation {
        let chord = try AssistantControls.codexChord("composer.toggleDictation",fallback:"cmd+shift+d")
        let win = try window()
        guard control(win, role:"AXButton", labels:["dictate","음성 입력"]) != nil else {
            throw CompanionError("현재 Codex 작성창에서 받아쓰기를 시작할 수 없습니다.")
        }
        try focusComposer(in:win)
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == AppProfile.codex.bundleIDs.first,
              CFEqual(try window().element,win.element) else { throw CompanionError("Codex 작성창이 바뀌었습니다.") }
        try DesktopShortcut.send(chord,to:.codex)
        return Dictation(window:win,stopChord:chord)
    }

    @MainActor static func endDictation(_ hold: Dictation) throws {
        let win = hold.window
        // A quick release can arrive while the composer is getting the microphone ready.
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        repeat {
            if let stop = control(win, role:"AXButton", labels:["stop dictation","음성 입력 중지","starting dictation; click to cancel","받아쓰기 시작 중, 클릭하여 취소"]) {
                if click(stop) { return }
                guard CFEqual(try window().element,win.element) else { throw CompanionError("Codex 작성창이 바뀌었습니다.") }
                try DesktopShortcut.send(hold.stopChord,to:.codex)
                return
            }
            Thread.sleep(forTimeInterval:0.045)
        } while ProcessInfo.processInfo.systemUptime < deadline
        if control(win, role:"AXButton", labels:["dictate","음성 입력"]) == nil {
            throw CompanionError("Codex 받아쓰기 종료 상태를 확인할 수 없습니다.")
        }
    }

    private static func focusComposer(in win:AppNode) throws {
        let editors = win.descendants { node in node.role == "AXTextArea" && node.identifier.contains("prosemirror") }
        let main = editors.filter { $0.ancestors.contains { $0.identifier.contains("composerlayoutbody-") } }
        let candidates = main.isEmpty ? editors : main
        guard candidates.count == 1,
              AXUIElementSetAttributeValue(candidates[0].element,"AXFocused" as CFString,kCFBooleanTrue) == .success else {
            throw CompanionError("Codex 작성창을 선택할 수 없습니다.")
        }
    }

    @MainActor static func submit() throws {
        try focusComposer(in:window())
        try DesktopShortcut.send("enter",to:.codex)
    }

    @MainActor static func fork() async throws {
        let win = try window()
        let headers = win.descendants { node in
            node.role == "AXPopUpButton" && node.ancestors.dropFirst().first?.role == "AXToolbar"
        }
        guard headers.count == 1 else { throw CompanionError("포크할 Codex 대화를 열어 주세요.") }
        func focusAndSend(_ key:String, to node:AppNode) throws {
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == AppProfile.codex.bundleIDs[0],
                  CFEqual(try window().element,win.element),
                  AXUIElementSetAttributeValue(node.element,"AXFocused" as CFString,kCFBooleanTrue) == .success else { throw CompanionError("대화 포커스가 바뀌었습니다.") }
            try DesktopShortcut.send(key,to:.codex)
        }
        func menuItem(_ labels:[String]) async throws -> AppNode {
            let deadline = ProcessInfo.processInfo.systemUptime + 1.5
            repeat {
                if let item = control(win,role:"AXMenuItem",labels:labels) { return item }
                try await Task.sleep(nanoseconds:50_000_000)
            } while ProcessInfo.processInfo.systemUptime < deadline
            throw CompanionError("현재 대화의 포크 메뉴를 확인할 수 없습니다.")
        }
        try focusAndSend("space",to:headers[0])
        let forkMenu = try await menuItem(["fork","포크","fork chat","채팅 포크"])
        if ["fork","포크"].contains(ClaudeControls.label(forkMenu).lowercased()) {
            try focusAndSend("right",to:forkMenu)
            let item = try await menuItem(["fork chat","채팅 포크","fork chat in same worktree","같은 워크트리에서 채팅 포크"])
            try focusAndSend("enter",to:item)
        } else {
            try focusAndSend("enter",to:forkMenu)
        }
    }
}
