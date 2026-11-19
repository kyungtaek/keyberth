import Foundation
import MicroCore

enum KeyMap {
    static let preferences = UserDefaults(suiteName: "local.kent.microcmux")!
    static let preference = "physicalKeyMappings"
    static let keys = (1...13).map { String(format: "K%02d", $0) }
    static let knob = ["ENC_CCW", "ENC_CW"]
    static let stick = ["JOY_UP", "JOY_DOWN", "JOY_LEFT", "JOY_RIGHT"]
    static let controls = keys + knob + stick + ["ENC_PRESS"]
    static let actions = (1...6).map { "최근 세션 \($0)" } + Deck.labels
        + ["이전 세션", "다음 세션", "위 패널로 이동", "아래 패널로 이동", "왼쪽 패널로 이동", "오른쪽 패널로 이동", "미할당"]
    static func code(_ input: DeckInput) -> String {
        switch input {
        case .key(let n): return String(format: "K%02d", n)
        case .knobPress: return "ENC_PRESS"
        case .turn(let delta): return delta < 0 ? knob[0] : knob[1]
        case .direction(let d): return "JOY_" + d.uppercased()
        }
    }
    static func name(_ code: String) -> String {
        if let i = keys.firstIndex(of: code) { return "키 \(i+1)" }
        if code == "ENC_PRESS" { return "노브 누름" }
        if let i = knob.firstIndex(of: code) { return ["노브 반시계 방향", "노브 시계 방향"][i] }
        if let i = stick.firstIndex(of: code) { return ["방향키 위", "방향키 아래", "방향키 왼쪽", "방향키 오른쪽"][i] }
        return code
    }
    static func label(_ binding: String) -> String {
        controls.firstIndex(of: binding).map { actions[$0] } ?? binding
    }
    static func load() -> [String:String] {
        let defaults = preferences
        if let saved = defaults.dictionary(forKey: preference) as? [String:String] { return saved }
        let legacy = defaults.dictionary(forKey: "functionShortcuts") as? [String:String] ?? [:]
        var result: [String:String] = [:]
        for (k, v) in legacy {
            if let n = Int(k), FunctionKey.range.contains(n), let chord = FunctionKey.shortcut(v) { result[keys[n]] = chord }
        }
        return result
    }
}
