import Foundation

public struct Key: Equatable {
    public let environment: String
    public let thread: String
    public init(environment: String, thread: String) {
        self.environment = environment
        self.thread = thread
    }
}

public struct Slots {
    private var identities: [Key] = []
    private var generation = UUID()
    private var observed: TimeInterval?
    public init() {}

    @discardableResult public mutating func update(_ sessions: [Key], now: TimeInterval) -> UUID {
        generation = UUID()
        observed = now
        identities = Array(sessions.prefix(6))
        return generation
    }

    public mutating func disconnect() {
        generation = UUID()
        observed = nil
        identities = []
    }

    public func resolve(_ slot: Int, generation expected: UUID, now: TimeInterval) -> Key? {
        guard generation == expected, let observed, now >= observed, now - observed <= 5,
              identities.indices.contains(slot) else { return nil }
        return identities[slot]
    }
}

public enum LED {
    public enum Invalid: Error { case colors }
    public static func frames(_ colors: [Int]) throws -> [[UInt8]] {
        guard colors.count == 6, colors.allSatisfy({ (0...0xffffff).contains($0) }) else { throw Invalid.colors }
        // Set brightness and a solid effect explicitly; the device retains omitted fields.
        let rpc: [String: Any] = ["method": "v.oai.thstatus",
                                 "params": colors.enumerated().map { ["id": $0.offset, "c": $0.element, "b": 1, "e": $0.element == 0 ? 0 : 1] }]
        return try basicFrames(rpc)
    }
}

public enum Probe: String, CaseIterable {
    case version = "sys.version"
    case status = "device.status"

    public func frames(id: Int) throws -> [[UInt8]] {
        try basicFrames(["id": id, "method": rawValue])
    }
}

func basicFrames(_ rpc: [String: Any]) throws -> [[UInt8]] {
        let payload = Array(try JSONSerialization.data(withJSONObject: rpc, options: [.sortedKeys])) + [10]
        return stride(from: 0, to: payload.count, by: 61).map { start in
            let chunk = Array(payload[start..<min(start + 61, payload.count)])
            return [6, 2, UInt8(chunk.count)] + chunk + Array(repeating: 0, count: 61 - chunk.count)
        }
}

public enum Input {
    private struct Event: Decodable {
        struct Parameters: Decodable { let k: String; let ag: Int; let act: Int }
        let method: String
        let params: Parameters
    }
    public static func slot(in payload: Data) -> Int? {
        guard payload.count <= 4096,
              let event = try? JSONDecoder().decode(Event.self, from: payload),
              event.method == "v.oai.hid", event.params.act == 1,
              (0..<6).contains(event.params.ag), event.params.k == "AG0\(event.params.ag)" else { return nil }
        return event.params.ag
    }
}
