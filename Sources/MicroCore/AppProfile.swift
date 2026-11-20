import Foundation

public enum AppProfile: String, CaseIterable {
    case cmux, slack, obsidian, t3, claude, codex

    public var title: String {
        switch self {
        case .cmux: return "cmux"
        case .slack: return "Slack"
        case .obsidian: return "Obsidian"
        case .t3: return "T3 Code"
        case .claude: return "Claude Desktop"
        case .codex: return "ChatGPT / Codex"
        }
    }

    public var bundleIDs: [String] {
        switch self {
        case .cmux: return ["com.cmuxterm.app"]
        case .slack: return ["com.tinyspeck.slackmacgap"]
        case .obsidian: return ["md.obsidian"]
        case .t3: return ["com.t3tools.t3code"]
        case .claude: return ["com.anthropic.claudefordesktop"]
        case .codex: return ["com.openai.codex"]
        }
    }

    public func advanced(by direction: Int) -> Self {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + (direction < 0 ? -1 : 1) + all.count) % all.count]
    }

    public static func fixedAction(_ input: String) -> String? {
        ["ENC_CW":"다음 키맵", "ENC_CCW":"이전 키맵", "ENC_PRESS":"자동 전환 켬/끔"][input]
    }

    public var hasRecentSessions: Bool { [.t3, .claude, .codex].contains(self) }

    public var agentActions: [String:String] {
        guard hasRecentSessions else { return [:] }
        var entries = Dictionary(uniqueKeysWithValues: (1...6).map { ("recent.\($0)", "최근 세션 \($0)") })
        if self == .t3 {
            for entry in Self.t3Controls { entries[entry.action] = entry.label }
        } else {
            entries.merge(["agent.fast": self == .claude ? "모델 · 사고 수준 선택" : "Fast 모드 전환",
                           "agent.approve":"이번 요청 승인", "agent.decline":"요청 거절", "agent.fork":"대화 분기",
                           "agent.mic":"마이크 받아쓰기", "agent.newChat":"새 대화", "agent.submit":"보내기", "agent.plan":self == .claude ? "계획 모드 선택" : "계획 모드 전환",
                           "agent.back":"이전 페이지", "agent.forward":"다음 페이지", "agent.sidebar":"사이드바 전환"]) { _, new in new }
        }
        return entries
    }

    private static let t3Controls: [(input:String, action:String, label:String)] = [
        ("JOY_DOWN","agent.terminal","터미널 열기/닫기"), ("JOY_RIGHT","agent.rightPanel","오른쪽 사이드 패널 열기/닫기"),
        ("K07","agent.nextPending","다음 입력 대기 세션"), ("K08","agent.approve","이번 요청 승인"),
        ("K09","agent.decline","요청 거부"), ("K10","agent.fork","현재 세션 포크"),
        ("K11","agent.dictate","음성 입력"), ("K12","agent.newChat","새 대화"), ("K13","agent.submit","보내기")
    ]

    public func defaultBinding(_ input: String) -> String {
        if self == .cmux { return input }
        if self == .slack { return SlackAction.binding(input) ?? "none" }
        if hasRecentSessions, let index = (1...6).first(where: { String(format:"K%02d", $0) == input }) { return "recent.\(index)" }
        if self == .t3, let control = Self.t3Controls.first(where:{ $0.input == input }) { return control.action }
        if self == .claude || self == .codex {
            return ["K07":"agent.fast","K08":"agent.approve","K09":"agent.decline","K10":"agent.fork","K11":"agent.mic","K12":"agent.newChat","K13":"agent.submit",
                    "JOY_UP":"agent.plan","JOY_DOWN":"agent.sidebar","JOY_LEFT":"agent.back","JOY_RIGHT":"agent.forward"][input] ?? "none"
        }
        let common = ["K11":"space", "K13":"enter", "JOY_LEFT":"left", "JOY_RIGHT":"right", "JOY_UP":"up", "JOY_DOWN":"down"]
        if let value = common[input] { return value }
        let presets: [String:String]
        switch self {
        case .slack: presets = [:]
        case .obsidian: presets = ["K01":"cmd+o","K02":"cmd+p","K03":"cmd+f","K07":"cmd+n"]
        case .t3, .claude, .codex: presets = ["K01":"cmd+c","K02":"cmd+v","K03":"cmd+f","K09":"escape"]
        case .cmux: presets = [:]
        }
        return presets[input] ?? "none"
    }
}
