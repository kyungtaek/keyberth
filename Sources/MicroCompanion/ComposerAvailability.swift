import AppKit
import MicroCore

enum ComposerAvailability {
    static let t3SendLabels = ["Submit message","Queue message","Steer message","Compact and send","Update queued message"]

    static func canSubmit(in profile:AppProfile, pid:pid_t) -> Bool {
        let root = AppNode(element:AXUIElementCreateApplication(pid))
        guard let window = root.node("AXFocusedWindow"), root.node("AXFocusedUIElement") != nil else { return false }
        let labels:[String]
        switch profile {
        case .codex: labels=["send","send message","submit","queue message","steer current turn","steer current task","현재 작업 조정","보내기","전송","메시지 보내기","대기열에 추가"]
        case .t3: labels=t3SendLabels.map { $0.lowercased() }
        case .claude: labels=["send","send message","메시지 보내기","보내기"]
        default: return false
        }
        // Find the action in the editor's container. Previous messages and sidebars can also have buttons.
        let editors = window.descendants({ node in
            guard node.role == "AXTextArea" else { return false }
            switch profile {
            case .t3: return node.identifier.contains("composer-tiptap")
            case .codex: return node.identifier.contains("prosemirror")
            default: return node.identifier.contains("prosemirror") || node.identifier.contains("tiptap")
            }
        })
        let editor:AppNode
        if profile == .codex {
            let main=editors.filter { $0.ancestors.contains { $0.identifier.contains("composerlayoutbody-") } }
            guard main.count == 1 else { return false }
            editor=main[0]
        } else {
            guard editors.count == 1 else { return false }
            editor=editors[0]
        }
        for parent in editor.ancestors.dropFirst().prefix(9) {
            if ["AXWindow","AXWebArea"].contains(parent.role) { break }
            let buttons=parent.descendants { $0.role == "AXButton" && labels.contains(ClaudeControls.label($0).lowercased()) }
            if !buttons.isEmpty { return buttons.count == 1 && buttons[0].attr("AXEnabled") as? Bool == true }
            if profile == .codex && parent.identifier.contains("composerlayoutbody-") { break }
        }
        return false
    }
}
