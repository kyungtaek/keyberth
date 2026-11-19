import CoreFoundation
import CryptoKit
import Foundation
import IOKit.hid
import MicroCore

extension USBDiscovery {
    struct Fingerprint: Equatable {
        let revision: Int
        let location: Int
        let descriptorSHA256: String

        init?(_ device: IOHIDDevice) {
            func integer(_ key: String) -> Int? {
                (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
            }
            guard (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String) == "USB",
                  integer(kIOHIDVendorIDKey) == 0x303a,
                  integer(kIOHIDProductIDKey) == 0x8360,
                  integer(kIOHIDPrimaryUsagePageKey) == 0xff00,
                  integer(kIOHIDPrimaryUsageKey) == 1,
                  let revision = integer(kIOHIDVersionNumberKey),
                  let location = integer(kIOHIDLocationIDKey), location != 0,
                  let descriptor = IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data,
                  !descriptor.isEmpty, descriptor.count <= 4096,
                  integer(kIOHIDMaxInputReportSizeKey) == 64,
                  integer(kIOHIDMaxOutputReportSizeKey) == 64 else { return nil }
            self.revision = revision
            self.location = location
            descriptorSHA256 = SHA256.hash(data: descriptor).map { String(format: "%02x", $0) }.joined()
        }
    }

    enum ProbeFailure: Error { case notConfirmed, notUnique, hid(Int32), timeout, malformed, mismatch }
    struct Result { let version: String }

    // No caller in the demo. The operator must separately attest the exact hardware and
    // its current firmware protocol; VID/PID or a descriptor alone are not attestation.
    static func readOnlyProbe(expected: Fingerprint, expectedVersion: String, operatorConfirmed: Bool) throws -> Result {
        guard operatorConfirmed, expectedVersion == "0.1.0-ai-micro-basic" else { throw ProbeFailure.notConfirmed }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(0))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: 0x303A, kIOHIDProductIDKey: 0x8360,
            kIOHIDDeviceUsagePageKey: 0xFF00, kIOHIDDeviceUsageKey: 1
        ] as CFDictionary)
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        let eligible = devices.filter { Fingerprint($0) == expected }
        guard eligible.count == 1, let device = eligible.first else { throw ProbeFailure.notUnique }

        guard !Thread.isMainThread, let loop = CFRunLoopGetCurrent() else { throw ProbeFailure.notConfirmed }
        let opened = IOHIDDeviceOpen(device, IOOptionBits(0))
        guard opened == kIOReturnSuccess else { throw ProbeFailure.hid(opened) }
        let mode = CFRunLoopMode(rawValue: "local.kent.micro.readonly" as CFString)
        let receiver = Receiver()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        defer {
            IOHIDDeviceUnscheduleFromRunLoop(device, loop, mode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(0))
            buffer.deallocate()
        }
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, result, _, type, reportID, bytes, count in
            guard let context else { return }
            let receiver = Unmanaged<Receiver>.fromOpaque(context).takeUnretainedValue()
            guard type == kIOHIDReportTypeInput, reportID == 6, receiver.response == nil else { return }
            guard result == kIOReturnSuccess, (63...64).contains(count) else { receiver.malformed = true; return }
            do {
                if let payload = try receiver.decoder.accept(id: reportID, bytes: Array(UnsafeBufferPointer(start: bytes, count: count))),
                   !ProbeReply.isInputNotification(payload) {
                    receiver.response = payload
                }
            } catch { receiver.malformed = true }
        }, Unmanaged.passUnretained(receiver).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, loop, mode.rawValue)

        func request(_ method: Probe, id: Int) throws -> Data {
            guard Fingerprint(device) == expected else { throw ProbeFailure.mismatch }
            receiver.decoder = Readback()
            receiver.response = nil
            receiver.malformed = false
            for frame in try method.frames(id: id) {
                let result = frame.withUnsafeBufferPointer {
                    IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 6, $0.baseAddress!, $0.count)
                }
                guard result == kIOReturnSuccess else { throw ProbeFailure.hid(result) }
            }
            let deadline = ProcessInfo.processInfo.systemUptime + 1
            while receiver.response == nil, !receiver.malformed {
                let remaining = deadline - ProcessInfo.processInfo.systemUptime
                guard remaining > 0 else { throw ProbeFailure.timeout }
                _ = CFRunLoopRunInMode(mode, min(remaining, 0.05), true)
            }
            guard !receiver.malformed, let response = receiver.response else { throw ProbeFailure.malformed }
            return response
        }

        let first = Int.random(in: 1...1_000_000_000)
        let version = try ProbeReply.version(request(.version, id: first), id: first)
        guard version == expectedVersion else { throw ProbeFailure.mismatch }
        let status = try ProbeReply.version(request(.status, id: first + 1), id: first + 1)
        guard status == version else { throw ProbeFailure.mismatch }
        return Result(version: version)
    }
}
private final class Receiver {
    var decoder = Readback()
    var response: Data?
    var malformed = false
}
