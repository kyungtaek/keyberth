import Foundation
import MicroCore

/// Tracks work before read/unread and foreground indicators are applied.
struct SessionActivity {
    struct Entry: Codable, Equatable {
        var state: String?
        var revision: String?
        var time: Double
    }
    private(set) var entries: [String:Entry] = [:]

    mutating func observe(id:String, light:SessionLight, revision:String? = nil,
                          initialTime:Double = 0, workTime:Double? = nil, now:Double) -> Double {
        let previous = entries[id]
        let state = light == .active ? SessionLight.ready : light
        let firstTime = initialTime == 0 && (state == .running || state == .attention) ? now : initialTime
        var entry = previous ?? Entry(time:firstTime)
        if let workTime { entry.time = max(entry.time, workTime) }
        if state != .unknown {
            if let old = entry.state, old != state.rawValue ||
                (entry.revision != nil && revision != nil && entry.revision != revision) {
                entry.time = max(entry.time,now)
            }
            entry.state = state.rawValue
            entry.revision = revision
        }
        if previous != entry { entries[id] = entry }
        return entry.time
    }
}
