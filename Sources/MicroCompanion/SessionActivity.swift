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

/// A connection starts with a silent snapshot. Track identities before any slot or focus changes.
struct SessionAlerts {
    private struct Observation {
        let state: SessionLight
        let revision: String?
        let time: Double
    }
    private var observations = [String:Observation]()
    private var lastPrune = 0.0

    mutating func observe(id:String, state:SessionLight, revision:String?, now:Double) -> String? {
        if now-lastPrune >= 60 {
            observations = observations.filter { now-$0.value.time < 60 }
            lastPrune = now
        }
        guard state != .unknown else { return nil }
        let previous = observations.updateValue(Observation(state:state, revision:revision, time:now), forKey:id)
        guard let previous, now-previous.time < 60 else { return nil }
        let newTurn = revision != nil && previous.revision != nil && revision != previous.revision
        guard previous.state != state || newTurn else { return nil }
        if state == .attention { return "attention" }
        if state == .done { return "done" }
        return nil
    }
}
