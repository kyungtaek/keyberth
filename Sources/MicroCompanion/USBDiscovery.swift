import Foundation
import IOKit.hid

enum USBDiscovery {
    // Registry enumeration only: no open, callbacks, device output or report requests.
    static func candidates() -> Int {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(0))
        let match: [String: Any] = [
            kIOHIDVendorIDKey: 0x303A, kIOHIDProductIDKey: 0x8360,
            kIOHIDDeviceUsagePageKey: 0xFF00, kIOHIDDeviceUsageKey: 1
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        return devices.filter { device in
            (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String) == "USB"
        }.count
    }
}
