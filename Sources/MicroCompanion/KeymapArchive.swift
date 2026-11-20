import Foundation
import MicroCore

struct KeymapArchive: Codable {
    let version:Int
    let profiles:[String:[String:String]]

    struct ClaudeSlots: Codable {
        let source:String
        let pins:[String:String]
        var valid:Bool {
            source.utf8.count <= 4096 && !source.contains("\0") && Set(pins.values).count == pins.count && pins.allSatisfy { slot,id in
                let prefix = "claude://claude.ai/epitaxy/local_"
                return (1...6).map(String.init).contains(slot) && id.hasPrefix(prefix) &&
                    UUID(uuidString:String(id.dropFirst(prefix.count))) != nil
            }
        }
    }
    let claudeSlots:ClaudeSlots?

    static func accepts(_ value:String, input:String, profile p:AppProfile) -> Bool {
        guard KeyMap.controls.contains(input), AppProfile.fixedAction(input) == nil, !value.isEmpty, value.utf8.count <= 4096 else { return false }
        if p == .cmux { return KeyMap.controls.contains(value) || FunctionKey.shortcut(value) != nil }
        return p.agentActions[value] != nil || value == "none" || DesktopShortcut.valid(value)
            || (p == .slack && SlackAction.input(value) != nil)
            || (p == .obsidian && KeyMap.keys.prefix(6).contains(input) && ObsidianNote.path(value) != nil)
    }
    func validate() throws {
        guard version == 1, !profiles.isEmpty, claudeSlots.map({ $0.valid && profiles["claudeCode"] != nil }) ?? true else { throw CompanionError("지원하지 않는 키맵 파일입니다.") }
        for (id,overrides) in profiles {
            guard let profile = AppProfile(rawValue:id), profile != .unconfigured else { throw CompanionError("알 수 없는 프로필 · "+id) }
            for (key,value) in overrides where !Self.accepts(value,input:key,profile:profile) {
                throw CompanionError("잘못된 키 매핑 · "+id+" / "+key)
            }
        }
    }
}
