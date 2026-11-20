import Foundation

public struct CmuxTarget: Equatable, Identifiable {
    public let id: UUID
    public let window: UUID
    public let workspace: UUID
    public let title: String
    public let active: Bool
    public internal(set) var tty: String? = nil

    public static func targets(_ data: Data) throws -> [Self] {
        struct Tree: Decodable { let windows: [Window] }
        struct Window: Decodable { let id: UUID; let workspaces: [Workspace] }
        struct Workspace: Decodable { let id: UUID; let title: String; let panes: [Pane] }
        struct Pane: Decodable { let surfaces: [Surface] }
        struct Surface: Decodable { let id: UUID; let title: String?; let type: String; let active: Bool?; let tty: String? }
        var targets: [Self] = []
        for window in try JSONDecoder().decode(Tree.self, from: data).windows {
            for workspace in window.workspaces {
                for surface in workspace.panes.flatMap(\.surfaces) where ["terminal", "agent-session"].contains(surface.type) {
                    targets.append(Self(id: surface.id, window: window.id, workspace: workspace.id,
                                        title: "\(workspace.title) · \(surface.title ?? surface.type)", active: surface.active == true, tty: surface.tty))
                }
            }
        }
        return targets
    }
    public func sameLocation(as other: Self) -> Bool {
        id == other.id && workspace == other.workspace && window == other.window
    }
}

public enum SessionLight: String, CaseIterable {
    case attention = "작업공간 입력 요청", running = "작업공간 실행 중", done = "작업공간 완료"
    case active = "현재 터미널", ready = "대기", unknown = "상태 미확인", empty = "빈 슬롯"
    public var rgb: Int {
        switch self {
        case .attention: return 0xFF9800
        case .running: return 0x268AFF
        case .done: return 0x31C56B
        case .active: return 0xFFFFFF
        case .ready: return 0xFFFFFF
        case .unknown: return 0x544D47
        case .empty: return 0
        }
    }
}

public struct WorkspaceSignal: Decodable {
    public let workspace_id: UUID
    let effective: String
    struct Signals: Decodable { let any_agent_needs_input: Bool; let any_agent_running: Bool }
    let signals: Signals
    public func light(active: Bool) -> SessionLight {
        if signals.any_agent_needs_input { return .attention }
        if signals.any_agent_running { return .running }
        if effective == "done" { return .done }
        return active ? .active : .ready
    }
}

public enum FunctionKey {
    public static let range = 6...12
    public static func index(in data: Data) -> Int? {
        struct Event: Decodable {
            struct Params: Decodable { let k: String; let act: Int }
            let method: String; let params: Params
        }
        guard data.count <= 4096, let event = try? JSONDecoder().decode(Event.self, from: data),
              event.method == "v.oai.hid", event.params.act == 1 else { return nil }
        return range.first { event.params.k == String(format: "ACT%02d", $0) }
    }

    public static let modifiers = ["cmd", "ctrl", "alt", "shift"]
    public static let specialKeys = ["enter", "escape", "tab", "backspace", "delete", "up", "down", "left", "right", "home", "end", "space"] + (1...12).map { "f\($0)" }

    public static func shortcut(_ value: String) -> String? {
        let parts = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "+")
        guard let key = parts.last else { return nil }
        let modifiers = Array(parts.dropLast())
        let allowed = Self.modifiers
        let letter = key.utf8.count == 1 && key.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) }
        guard Set(modifiers).count == modifiers.count, modifiers.allSatisfy(allowed.contains),
              specialKeys.contains(key) || ((letter || ["=", "-", "[", "]"].contains(key)) && !modifiers.isEmpty) else { return nil }
        return (allowed.filter(modifiers.contains) + [key]).joined(separator: "+")
    }
}

extension SessionLight {
    public var agentCode: String {
        switch self {
        case .empty, .unknown: return "0"
        case .active, .ready: return "1"
        case .running: return "2"
        case .attention: return "3"
        case .done: return "4"
        }
    }
}
