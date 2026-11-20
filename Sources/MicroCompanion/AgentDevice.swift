import Foundation
import IOKit
import IOKit.serial
import IOKit.hid
import MicroCore

struct CompanionError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum AgentDevice {
    static let firmware = "0.2.18-ai-micro-agent"

    // Walk up from the callout node to its USB device. The location also ties
    // the CDC version reply to the HID collection used for input and lights.
    static func port() throws -> (path: String, location: Int, instance: UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOSerialBSDServiceValue), &iterator) == KERN_SUCCESS else {
            throw CompanionError("USB 시리얼 목록을 읽을 수 없습니다.")
        }
        defer { IOObjectRelease(iterator) }
        var matches: [(String, Int, UInt64)] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            func property(_ key: String) -> Any? {
                IORegistryEntrySearchCFProperty(entry, kIOServicePlane, key as CFString, nil,
                    IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
            }
            guard let path = property(kIOCalloutDeviceKey) as? String,
                  path.hasPrefix("/dev/cu.usbmodem"),
                  property("idVendor") as? Int == 0x303a, property("idProduct") as? Int == 0x8360,
                  let location = property("locationID") as? Int else { continue }
            var instance: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(entry, &instance) == KERN_SUCCESS else { continue }
            matches.append((path, location, instance))
        }
        guard matches.count == 1 else { throw CompanionError("AI Micro USB 연결 \(matches.count)개 · 한 대를 연결하세요.") }
        return matches[0]
    }

    static func withSerial<T>(_ path: String, perform: (Int32) throws -> T) throws -> T {
        let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw CompanionError("USB 포트를 열 수 없습니다. 사용 중인 앱을 확인하세요.") }
        defer { close(fd) }
        guard ioctl(fd, TIOCEXCL) == 0 else { throw CompanionError("USB 포트를 사용할 수 없습니다.") }
        var original = termios()
        guard tcgetattr(fd, &original) == 0 else { throw CompanionError("USB 통신 설정 조회 실패") }
        defer { tcsetattr(fd, TCSANOW, &original) }
        var mode = original
        cfmakeraw(&mode)
        cfsetspeed(&mode, speed_t(B115200))
        guard tcsetattr(fd, TCSANOW, &mode) == 0 else { throw CompanionError("USB 통신 설정 실패") }
        tcflush(fd, TCIFLUSH)
        return try perform(fd)
    }

    static func query(_ fd: Int32, command: String, prefix: String) throws -> Data {
        let bytes = Array((command + "\n").utf8)
        guard write(fd, bytes, bytes.count) == bytes.count else { throw CompanionError("USB 명령 전송 실패") }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 2048)
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while ProcessInfo.processInfo.systemUptime < deadline {
            var item = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&item, 1, 100) > 0 else { continue }
            let count = read(fd, &buffer, buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
            while let end = data.firstIndex(of: 10) {
                let line = data[..<end]
                data.removeSubrange(...end)
                let header = Data((prefix + "\t").utf8)
                if line.starts(with: header) { return Data(line.dropFirst(header.count)) }
            }
            if data.count > 16384 { break }
        }
        throw CompanionError("USB 응답 시간 초과 · " + prefix)
    }

    static func verify(_ fd: Int32) throws {
        let data = try query(fd, command: "UPDATE_INFO", prefix: "CMUPDATE_INFO")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard json?["firmwareVersion"] as? String == firmware,
              json?["hardwareRevision"] as? String == "AI Micro" else {
            throw CompanionError("지원 대상과 다른 펌웨어입니다.")
        }
    }

    static func verify(_ path: String) throws {
        try withSerial(path, perform: verify)
    }

}

final class AgentHID {
    private let device: IOHIDDevice
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 20)
    private let session = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    private let status: (String) -> Void
    private let release: (DeckInput) -> Void
    private let press: (DeckInput) -> Void
    private var decoder = UniversalAgent.Decoder()
    private var timer: Timer?
    private var seq = 0, inputSeq = 0
    private var stage = 0
    private var pending: (name: String, value: String?, deadline: TimeInterval)?
    private let location: Int
    private var wantedLighting: LightingOutput.Frame?
    private var lastLighting: LightingOutput.Frame?
    private var nextLightingAttempt = 0.0
    private var lightingBusy = false
    private(set) var lightingStatus = ""
    func retryLighting() { lastLighting = nil }
    private func applyLighting() {
        guard !lightingBusy, now >= nextLightingAttempt, let desired = wantedLighting, desired != lastLighting else { return }
        lightingBusy = true
        lastLighting = desired
        lightingStatus = "조명 적용 중"
        let location = self.location
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let message: String, failed: Bool
            do { try LightingOutput.apply(desired,location:location); message = "기기에서 조명 설정 수신"; failed = false }
            catch { message = error.localizedDescription; failed = true }
            DispatchQueue.main.async { [weak self, message] in
                guard let self, !self.stopped else { return }
                if failed { self.lastLighting = nil; self.nextLightingAttempt = self.now + 3 }
                self.lightingBusy = false
                self.lightingStatus = message
            }
        }
    }
    private var frame: String?, selected: String?
    private var sentFrame: String?, sentSelected: String?
    private var lastWrite = 0.0
    private var stopped = false
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    init(location: Int, status: @escaping (String) -> Void, release: @escaping (DeckInput) -> Void = { _ in }, press: @escaping (DeckInput) -> Void) throws {
        self.location = location
        self.status = status
        self.release = release
        self.press = press
        let manager = IOHIDManagerCreate(nil, 0)
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDTransportKey: "USB", kIOHIDVendorIDKey: 0x303a,
            kIOHIDProductIDKey: 0x8360, kIOHIDDeviceUsagePageKey: 0xff31, kIOHIDDeviceUsageKey: 1] as CFDictionary)
        let matches = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []).filter {
            IOHIDDeviceGetProperty($0, kIOHIDLocationIDKey as CFString) as? Int == location
        }
        guard matches.count == 1, let device = matches.first, IOHIDDeviceOpen(device, 0) == 0 else {
            buffer.deallocate()
            throw CompanionError("Universal Agent USB HID 연결 실패")
        }
        self.device = device
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 20, { ctx, result, _, type, id, bytes, count in
            guard let ctx, result == 0, type == kIOHIDReportTypeInput, id == 7, (19...20).contains(count) else { return }
            let client = Unmanaged<AgentHID>.fromOpaque(ctx).takeUnretainedValue()
            if let line = try? client.decoder.accept(Array(UnsafeBufferPointer(start: bytes, count: count))) {
                client.receive(line)
            }
        }, ctx)
        IOHIDDeviceRegisterRemovalCallback(device, { ctx, _, _ in
            if let ctx { Unmanaged<AgentHID>.fromOpaque(ctx).takeUnretainedValue().fail("USB 연결 해제") }
        }, ctx)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        tick()
    }
    func display(_ states: [SessionLight], selected index: Int?, palette:SessionLighting? = nil) {
        guard states.count == 6 else { return }
        wantedLighting = LightingOutput.Frame(palette:palette ?? .initial,states:states,selected:index,includeAmbient:palette != nil)
        frame = states.map(\.agentCode).joined()
        selected = String(index.map { $0 + 1 } ?? 0)
    }
    private func write(_ line: String) throws {
        for part in try UniversalAgent.frames(line) {
            let result = part.withUnsafeBufferPointer { IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 7, $0.baseAddress!, $0.count) }
            guard result == 0 else { throw CompanionError("USB 리포트 전송 실패") }
        }
    }
    private func command(_ name: String, _ value: String? = nil) throws {
        var fields = [name, session]
        if name != "AMHELLO" { seq += 1; fields.append(String(seq)) }
        if let value { fields.append(value) }
        lastWrite = now
        pending = (name, value, now + 2)
        try write(fields.joined(separator: "\t"))
    }
    private func tick() {
        guard !stopped else { return }
        if let pending {
            if now >= pending.deadline { fail(pending.name + " 응답 시간 초과") }
            return
        }
        do {
            switch stage {
            case 0: try command("AMHELLO")
            case 1: try command("AMMODE", "generic")
            case 2: try command("AMKEYMODE", "sessions")
            default:
                if let frame, frame != sentFrame { try command("AMFRAME", frame) }
                else if let selected, selected != sentSelected { try command("AMSELECT", selected) }
                else {
                    applyLighting()
                    if now - lastWrite >= 1 { try command("AMHEARTBEAT") }
                }
            }
        } catch { fail(error.localizedDescription) }
    }
    private func receive(_ line: String) {
        guard !stopped, let tab = line.firstIndex(of: "\t") else { return }
        let kind = line[..<tab], payload = String(line[line.index(after: tab)...])
        switch kind {
        case "AMHELLO":
            guard pending?.name == "AMHELLO",
                  let obj = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                  obj["session"] as? String == session else { return }
            guard obj["version"] as? String == AgentDevice.firmware, obj["protocol"] as? String == "ai-micro-agent-v1",
                  obj["hardware"] as? String == "AI Micro", obj["slots"] as? Int == 6,
                  let caps = obj["capabilities"] as? [String], ["input-events","slot-states","selected-slot"].allSatisfy(caps.contains)
            else { fail("지원 대상과 다른 Universal Agent 펌웨어"); return }
            pending = nil
            stage = 1
        case "AMACK":
            guard let request = pending, request.name != "AMHELLO", Int(payload) == seq else { return }
            pending = nil
            switch request.name {
            case "AMMODE": stage = 2
            case "AMKEYMODE": stage = 3; status("USB 연결됨 · " + AgentDevice.firmware)
            case "AMFRAME": lastLighting = nil; sentFrame = request.value; trace("frame ACK " + (sentFrame ?? ""))
            case "AMSELECT": lastLighting = nil; sentSelected = request.value; trace("selected ACK " + (sentSelected ?? ""))
            default: break
            }
        case "AMINPUT":
            struct Event: Decodable { let session: String; let seq: Int; let id: String; let pressed: Bool }
            guard stage == 3, let e = try? JSONDecoder().decode(Event.self, from: Data(payload.utf8)),
                  e.session == session, e.seq > inputSeq else { return }
            guard e.seq == inputSeq + 1 else { fail("USB 입력 순서 불일치"); return }
            inputSeq = e.seq
            trace("input \(e.seq) \(e.id) \(e.pressed)")
            if let input = DeckInput(id: e.id) { (e.pressed ? press : release)(input) }
        case "MKERR": fail("기기가 명령을 거부했습니다 · " + String(payload.prefix(80)))
        default: break
        }
    }
    private func trace(_ value: String) {
        if CommandLine.arguments.contains("--agent-diagnostics") { fputs(value + "\n", stderr) }
    }
    private func fail(_ reason: String) {
        lightingStatus = "USB 재연결 필요"
        stopped = true
        timer?.invalidate()
        status(reason + " · 다시 연결하세요.")
    }
    func close() {
        if !stopped && stage > 0 { try? command("AMBYE") }
        stopped = true
        timer?.invalidate()
    }
    deinit {
        timer?.invalidate()
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceClose(device, 0)
        buffer.deallocate()
    }
}
