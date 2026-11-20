import Foundation

/// A completed turn is green until viewed. A session first encountered with
/// historical completion starts idle; reordering slots does not create a turn.
public struct CompletionIndicator {
    private struct Entry {
        var last: SessionLight
        var unread: Bool
        var revision: String?
    }
    private var entries: [String:Entry] = [:]
    public init() {}
    public mutating func display(_ state: SessionLight, id: String, revision: String? = nil, viewed: Bool = false) -> SessionLight {
        let previous = entries[id]
        let newTurn = previous.map { $0.last != .done || (revision != nil && $0.revision != revision) } ?? false
        let unread = state == .done && !viewed && (newTurn || previous?.unread == true)
        entries[id] = Entry(last:state, unread:unread, revision:revision)
        return state == .done && !unread ? .ready : state
    }
    public mutating func markViewed(_ id:String) { entries[id]?.unread = false }
}
