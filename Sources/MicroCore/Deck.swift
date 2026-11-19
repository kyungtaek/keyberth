import Foundation

public enum DeckInput: Equatable {
    case key(Int), turn(Int), direction(String)

    public init?(id: String) {
        switch id {
        case "ENC_CCW": self = .turn(-1)
        case "ENC_CW": self = .turn(1)
        case "JOY_LEFT", "JOY_RIGHT", "JOY_UP", "JOY_DOWN":
            self = .direction(id.dropFirst(4).lowercased())
        default:
            guard let n = (1...13).first(where: { id == String(format: "K%02d", $0) }) else { return nil }
            self = .key(n)
        }
    }
}

public enum Deck {
    public static let labels = ["새 워크스페이스", "이번 요청 승인", "요청 거부", "오른쪽 사이드 패널", "스페이스", "오른쪽에 대화 포크", "엔터"]

    public static func recent(live: [CmuxTarget], history: [UUID]) -> [CmuxTarget] {
        var used = Set<UUID>()
        let ordered = live.filter(\.active) + history.compactMap { id in live.first { $0.id == id } } + live
        return Array(ordered.filter { used.insert($0.id).inserted }.prefix(6))
    }
}
