import Foundation

struct DevicePreferences: Decodable {
    let brightness: Int?
    let styles: [String]?
    let revision: UInt32
    let version, sleepMinutes, volumePercent, standbyMinutes: Int
    let standbyPowered, standbyBluetooth, storageReady, buzzerEnabled: Bool

    struct Snapshot {
        let instance: UInt64
        let value: DevicePreferences
    }

    private static func request(_ fd: Int32, _ command: String, _ fields: [String: Any] = [:]) throws -> Self {
        let id = UInt32.random(in: 1...UInt32.max)
        var body = fields
        body["id"] = id
        let payload = try JSONSerialization.data(withJSONObject: body)
        let response = try AgentDevice.query(fd, command: command + "\t" + String(decoding: payload, as: UTF8.self), prefix: "CMPREFS")
        struct Reply: Decodable { let id: UInt32; let ok: Bool; let error: String? }
        let reply = try JSONDecoder().decode(Reply.self, from: response)
        guard reply.id == id else { throw CompanionError("응답이 일치하지 않습니다. 다시 읽어 주세요.") }
        guard reply.ok else { throw CompanionError("설정을 저장할 수 없습니다 · " + (reply.error ?? command)) }
        let prefs = try JSONDecoder().decode(Self.self, from: response)
        guard prefs.version == 1, prefs.storageReady, (0...120).contains(prefs.sleepMinutes),
              (0...100).contains(prefs.volumePercent), (1...120).contains(prefs.standbyMinutes) else {
            throw CompanionError("기기의 설정 형식이나 저장 상태를 확인하세요.")
        }
        return prefs
    }

    static func read() throws -> Snapshot {
        let port = try AgentDevice.port()
        return try AgentDevice.withSerial(port.path) { fd in
            guard [AgentDevice.firmware,"0.3.0-keyberth",AgentDevice.developmentFirmware].contains(try AgentDevice.verify(fd)) else {
                throw CompanionError("기기 설정을 사용하려면 키버스-펌웨어 0.3.0 이상이 필요합니다.")
            }
            return Snapshot(instance: port.instance, value: try request(fd, "PREFS_GET"))
        }
    }

    static func save(_ old: Snapshot, sleep: Int, volume: Int, brightness: Int?, styles: [String]?) throws -> Snapshot {
        let port = try AgentDevice.port()
        guard port.instance == old.instance else { throw CompanionError("연결된 기기가 변경됐습니다. 설정을 다시 읽어 주세요.") }
        return try AgentDevice.withSerial(port.path) { fd in
            guard [AgentDevice.firmware,"0.3.0-keyberth",AgentDevice.developmentFirmware].contains(try AgentDevice.verify(fd)) else {
                throw CompanionError("기기 설정을 사용하려면 키버스-펌웨어 0.3.0 이상이 필요합니다.")
            }
            let previous = old.value
            var fields: [String:Any] = ["version": 1, "revision": previous.revision,
                "sleepMinutes": sleep, "volumePercent": volume, "standbyMinutes": previous.standbyMinutes,
                "standbyPowered": previous.standbyPowered, "standbyBluetooth": previous.standbyBluetooth]
            if previous.brightness != nil {
                fields["brightness"] = brightness ?? previous.brightness
                fields["styles"] = styles ?? previous.styles
            }
            let confirmed = try request(fd,"PREFS_SET",fields)
            let actual = try request(fd, "PREFS_GET")
            for result in [confirmed, actual] {
                guard result.revision == previous.revision &+ 1, result.sleepMinutes == sleep,
                      result.volumePercent == volume,
                      result.brightness == (brightness ?? previous.brightness), result.styles == (styles ?? previous.styles), result.standbyMinutes == previous.standbyMinutes,
                      result.standbyPowered == previous.standbyPowered, result.standbyBluetooth == previous.standbyBluetooth else {
                    throw CompanionError("저장 후 읽은 값이 다릅니다. 다시 읽어 주세요.")
                }
            }
            return Snapshot(instance: port.instance, value: actual)
        }
    }
}
