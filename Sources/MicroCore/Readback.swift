import Foundation

public struct Readback {
    public enum Invalid: Error { case frame }
    private var accumulated = Data()
    public init() {}

    public mutating func accept(id: UInt32, bytes: [UInt8]) throws -> Data? {
        do {
            guard id == 6 else { throw Invalid.frame }
            let slice: ArraySlice<UInt8>
            switch bytes.count {
            case 64 where bytes[0] == 6: slice = bytes.dropFirst()
            case 63: slice = bytes[...]
            default: throw Invalid.frame
            }
            guard slice.first == 2 else { throw Invalid.frame }
            let length = Int(slice[slice.startIndex + 1])
            guard (1...61).contains(length), slice.dropFirst(2 + length).allSatisfy({ $0 == 0 }),
                  accumulated.count + length <= 4096 else { throw Invalid.frame }
            let packet = slice.dropFirst(2).prefix(length)
            guard !packet.dropLast().contains(10) else { throw Invalid.frame }
            accumulated.append(contentsOf: packet)
            guard accumulated.last == 10 else { return nil }
            let ready = accumulated
            accumulated.removeAll()
            return ready
        } catch {
            accumulated.removeAll()
            throw error
        }
    }
}

public enum ProbeReply {
    public enum Invalid: Error { case response }

    public static func isInputNotification(_ data: Data) -> Bool {
        guard data.count <= 4096,
              let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              Set(event.keys) == ["method", "params"],
              let method = event["method"] as? String,
              event["params"] is [String: Any] else { return false }
        return method == "v.oai.hid" || method == "v.oai.rad"
    }
    public static func version(_ data: Data, id: Int) throws -> String {
        struct Value: Decodable { let version: String }
        struct Response: Decodable { let id: Int; let result: Value; let error: Bool? }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.id == id, response.error == nil,
              !response.result.version.isEmpty, response.result.version.utf8.count <= 128 else { throw Invalid.response }
        return response.result.version
    }
}
