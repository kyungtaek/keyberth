import Foundation

public enum AppProfile: RawRepresentable, Hashable, CaseIterable {
    case cmux, slack, obsidian, t3, claude, codex, claudeCode

    case application(String), unconfigured

    public static let allCases: [Self] = [.cmux,.t3,.codex,.claude,.claudeCode]
    public static let initial: [Self] = [.cmux,.t3,.codex,.claude,.claudeCode]
    public var rawValue:String {
        switch self {
        case .cmux:return "cmux"
        case .t3:return "t3"
        case .codex:return "codex"
        case .claude:return "claude"
        case .claudeCode:return "claudeCode"
        case .slack:return "slack"
        case .obsidian:return "obsidian"
        case .unconfigured:return "unconfigured"
        case .application(let id):return "app."+id
        }
    }
    public init?(rawValue:String) {
        if let known=(Self.allCases + [.slack,.obsidian,.unconfigured]).first(where:{$0.rawValue==rawValue}) { self=known;return }
        guard rawValue.hasPrefix("app."),rawValue.count<=260 else {return nil}
        let id=String(rawValue.dropFirst(4))
        guard id.range(of:"^[A-Za-z0-9-]+([.][A-Za-z0-9-]+)+$",options:.regularExpression) != nil else {return nil}
        self = .application(id)
    }
    public var selectable:Bool { self != .slack && self != .obsidian && self != .unconfigured }
    public var title: String {
        switch self {
        case .application(let id):return id
        case .unconfigured:return "키맵 없음"
        case .cmux: return "cmux"
        case .slack: return "Slack"
        case .obsidian: return "Obsidian"
        case .t3: return "T3 Code"
        case .claude: return "Claude Desktop"
        case .codex: return "Codex Desktop"
        case .claudeCode: return "Claude Code · 세션"
        }
    }

    public var bundleIDs: [String] {
        switch self {
        case .application(let id):return [id]
        case .unconfigured:return []
        case .cmux: return ["com.cmuxterm.app"]
        case .slack: return ["com.tinyspeck.slackmacgap"]
        case .obsidian: return ["md.obsidian"]
        case .t3: return ["com.t3tools.t3code"]
        case .claude: return ["com.anthropic.claudefordesktop"]
        case .codex: return ["com.openai.codex"]
        case .claudeCode: return [] // Alternate modes of the same foreground apps.
        }
    }

    public var hasRecentSessions: Bool { [.t3, .claudeCode, .claude, .codex].contains(self) }

    public var agentActions: [String:String] {
        if self == .cmux {
            return ["agent.stop":"터미널 작업 중단 (SIGINT)", "agent.wake":"최대 절전 에이전트 깨우기",
                    "agent.hibernate":"에이전트 최대 절전", "agent.splitRight":"오른쪽 터미널 분할", "agent.splitDown":"아래 터미널 분할"]
        }
        guard hasRecentSessions else { return [:] }
        var entries = Dictionary(uniqueKeysWithValues: (1...6).map { ("recent.\($0)", "최근 세션 \($0)") })
        if self == .claudeCode {
            entries.merge(["agent.approve":"이번 요청 승인", "agent.decline":"요청 거절"]) { _, new in new }
        } else if self == .t3 {
            for command in Self.t3Commands { entries["agent.t3."+command.id] = command.label }
            entries["agent.resume"] = "현재 대화 재개"
            entries["agent.decline"] = "요청 거부"
            entries["agent.nextPending"] = "다음 입력 대기 세션"
            for entry in Self.t3Controls { entries[entry.action] = entry.label }
        } else {
            entries.merge(["agent.fast": self == .claude ? "모델 · 사고 수준 선택" : "Fast 모드 전환",
                           "agent.approve":"이번 요청 승인", "agent.decline":"요청 거절", "agent.fork":"대화 분기",
                           "agent.mic":"누르고 받아쓰기", "agent.newChat":"새 대화", "agent.submit":"보내기", "agent.plan":self == .claude ? "계획 모드 선택" : "계획 모드 전환",
                           "agent.back":"이전 페이지", "agent.forward":"다음 페이지", "agent.sidebar":"사이드바 전환"]) { _, new in new }
        }
        if self == .codex {
            entries["agent.modelNext"] = "다음 모델"
            entries["agent.modelPrevious"] = "이전 모델"
            entries["agent.effortUp"] = "추론 노력 높이기"
            entries["agent.effortDown"] = "추론 노력 낮추기"
            entries["agent.dots"] = "내 Dots 열기"
            entries["agent.stop"] = "현재 응답 중단"
            entries["agent.resume"] = "현재 대화 재개"
        }
        return entries
    }

    public static let t3Commands: [(id:String,label:String,chord:String)] = [
        ("commandPalette.toggle","명령 팔레트","cmd+k"), ("filePicker.toggle","파일 열기","cmd+p"),
        ("projectSearch.toggle","프로젝트 내용 검색","cmd+shift+f"), ("chat.find","대화에서 찾기","cmd+f"),
        ("chat.newLocal","새 로컬 대화","cmd+shift+n"), ("chat.newWithoutProject","프로젝트 없이 새 대화","cmd+alt+n"),
        ("thread.previous","이전 대화","cmd+shift+["), ("thread.next","다음 대화","cmd+shift+]"),
        ("thread.copyReference","대화 참조 복사","cmd+shift+c"), ("thread.pin","대화 고정 전환","cmd+shift+p"),
        ("threadPanel.toggle","대화 패널 전환","cmd+shift+b"), ("view.reopenClosed","닫은 보기 다시 열기","cmd+shift+t"),
        ("sidebar.toggle","사이드바 전환","cmd+b"), ("navigation.back","뒤로 이동","cmd+["),
        ("navigation.forward","앞으로 이동","cmd+]"), ("usage.open","사용량 열기","cmd+u"),
        ("theme.select","테마 선택","cmd+alt+a"), ("appearance.cycle","화면 모드 순환","cmd+alt+shift+a"),
        ("themeEditor.toggle","테마 편집기","cmd+alt+shift+t"), ("composer.stash","작성 중인 입력 보관","cmd+s"),
        ("modelPicker.toggle","모델 선택","cmd+shift+m"), ("composer.host","호스트 선택","cmd+shift+h"),
        ("composer.effort","추론 수준 선택","cmd+shift+e"), ("composer.mode","대화 모드 선택","cmd+shift+a"),
        ("composer.workspace","작업공간 선택","cmd+shift+x"), ("composer.branch","브랜치 선택","cmd+shift+g"),
        ("composer.previousWorktree","이전 워크트리","cmd+shift+l"), ("preview.toggle","미리보기 전환","cmd+shift+j"),
        ("workspace.focusNext","다음 영역 포커스","f6"), ("workspace.focusPrevious","이전 영역 포커스","shift+f6")
    ]

    private static let t3Controls: [(input:String, action:String, label:String)] = [
        ("JOY_DOWN","agent.terminal","터미널 열기/닫기"), ("JOY_RIGHT","agent.rightPanel","오른쪽 사이드 패널 열기/닫기"),
        ("K07","agent.newChat","새 대화"), ("K08","agent.approve","이번 요청 승인"),
        ("K09","agent.settle","현재 세션 정리"), ("K10","agent.fork","현재 세션 포크"),
        ("K11","agent.dictate","누르고 받아쓰기"), ("K12","agent.stop","현재 진행 중단"), ("K13","agent.submit","보내기")
    ]

    public func defaultBinding(_ input: String) -> String {
        if case .application = self {return "none"}
        if self == .unconfigured {return "none"}
        if self == .codex {
            if let slot=(1...6).first(where:{String(format:"K%02d",$0)==input}) {return "recent."+String(slot)}
            return ["K07":"agent.dots","K08":"agent.approve","K09":"agent.decline","K10":"agent.fork","K11":"agent.mic","K12":"agent.newChat","K13":"agent.submit",
                    "JOY_UP":"agent.plan","JOY_RIGHT":"agent.forward","JOY_DOWN":"agent.sidebar","JOY_LEFT":"agent.back"][input] ?? "none"
        }
        if self == .cmux { return input }
        if self == .slack { return SlackAction.binding(input) ?? "none" }
        let arrows = ["JOY_UP":"up","JOY_DOWN":"down","JOY_LEFT":"left","JOY_RIGHT":"right"]
        if self == .claude || self == .claudeCode {
            if let arrow=arrows[input] { return arrow }
            let claudeKeys=["cmd+b","ctrl+cmd+f","cmd+=","cmd+-","ctrl+shift+tab","ctrl+tab","escape","cmd+a","backspace","cmd+z","cmd+d","cmd+n","enter"]
            if let index=(1...13).first(where:{ String(format:"K%02d",$0) == input }) {
                if self == .claudeCode {
                    if index <= 6 { return "recent."+String(index) }
                }
                return claudeKeys[index-1]
            }
        }
        if hasRecentSessions, let index = (1...6).first(where: { String(format:"K%02d", $0) == input }) { return "recent.\(index)" }
        if self == .t3, let control = Self.t3Controls.first(where:{ $0.input == input }) { return control.action }
        let common = ["K11":"space", "K13":"enter", "JOY_LEFT":"left", "JOY_RIGHT":"right", "JOY_UP":"up", "JOY_DOWN":"down"]
        if let value = common[input] { return value }
        let presets: [String:String]
        switch self {
        case .slack: presets = [:]
        case .obsidian: presets = ["K01":"cmd+o","K02":"cmd+p","K03":"cmd+f","K07":"cmd+n"]
        case .t3, .claude, .codex, .claudeCode: presets = ["K01":"cmd+c","K02":"cmd+v","K03":"cmd+f","K09":"escape"]
        case .cmux,.application,.unconfigured: presets = [:]
        }
        return presets[input] ?? "none"
    }
}
