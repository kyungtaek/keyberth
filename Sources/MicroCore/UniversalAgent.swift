import Foundation

/// USB vendor collection FF31/1, report 7. Flag bits delimit one ASCII command.
public enum UniversalAgent {
    public enum Failure: Error { case invalidFrame, invalidCommand }
    public static func frames(_ command: String) throws -> [[UInt8]] {
        let data = Array(command.utf8)
        guard (1...128).contains(data.count), data.allSatisfy({ $0 == 9 || (32...126).contains($0) }) else { throw Failure.invalidCommand }
        return stride(from: 0, to: data.count, by: 15).map { i in
            let part = data[i..<min(i + 15, data.count)]
            let flags: UInt8 = (i == 0 ? 1 : 0) | (i + part.count == data.count ? 2 : 0)
            return [7, 0xa1, flags, UInt8(i / 15), UInt8(part.count)] + part + Array(repeating: 0, count: 15 - part.count)
        }
    }
    public struct Decoder {
        private var data = Data()
        private var next: Int?
        public init() {}
        public mutating func accept(_ raw: [UInt8]) throws -> String? {
            let bytes = raw.count == 20 && raw.first == 7 ? raw.dropFirst() : raw[...]
            let b = Array(bytes)
            guard b.count == 19, b[0] == 0xa1, b[1] < 4, (1...15).contains(b[3]) else { self = Self(); throw Failure.invalidFrame }
            if b[1] & 1 != 0 { data.removeAll(); next = 0 }
            guard next == Int(b[2]), data.count + Int(b[3]) <= 2048 else { self = Self(); throw Failure.invalidFrame }
            data.append(contentsOf: b[4..<(4+Int(b[3]))])
            next = Int(b[2]) + 1
            guard b[1] & 2 != 0 else { return nil }
            defer { self = Self() }
            guard let line = String(data: data, encoding: .utf8) else { throw Failure.invalidFrame }
            return line
        }
    }
}
