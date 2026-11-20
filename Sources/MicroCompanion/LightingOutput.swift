import Foundation
import IOKit.hid
import MicroCore

// Short-lived report 6 transaction on a worker run loop. Report 7 independently
// retains the input session and heartbeat while the two lighting RPCs complete.
final class LightingOutput {
    struct Frame: Equatable {
        let palette: SessionLighting
        let states: [SessionLight]
        let selected: Int?
        let includeAmbient: Bool
        var firmwareSlot:Int? = nil
    }
    private var decoder = Readback()
    private var waiting = 0
    private var accepted: Bool?

    static func apply(_ frame:Frame, location:Int) throws {
        let manager = IOHIDManagerCreate(nil,0)
        IOHIDManagerSetDeviceMatching(manager,[kIOHIDTransportKey:"USB",kIOHIDVendorIDKey:0x303a,
            kIOHIDProductIDKey:0x8360,kIOHIDDeviceUsagePageKey:0xff00,kIOHIDDeviceUsageKey:1] as CFDictionary)
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []).filter {
            IOHIDDeviceGetProperty($0,kIOHIDLocationIDKey as CFString) as? Int == location
        }
        guard devices.count == 1, let device=devices.first, IOHIDDeviceOpen(device,0)==0 else { throw CompanionError("조명 USB 연결 실패") }
        guard let loop = CFRunLoopGetCurrent() else { IOHIDDeviceClose(device,0); throw CompanionError("조명 응답 수신 준비 실패") }
        let receiver = LightingOutput()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity:64)
        IOHIDDeviceRegisterInputReportCallback(device,buffer,64,{ ctx,status,_,_,id,bytes,n in
            guard let ctx,status==0,id==6,(63...64).contains(n) else { return }
            let receiver=Unmanaged<LightingOutput>.fromOpaque(ctx).takeUnretainedValue()
            guard let data = try? receiver.decoder.accept(id:id,bytes:Array(UnsafeBufferPointer(start:bytes,count:n))),
                  let value = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
                  value["id"] as? Int == receiver.waiting else { return }
            receiver.accepted = value["result"] as? Bool == true && value["error"] == nil
        },Unmanaged.passUnretained(receiver).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device,loop,CFRunLoopMode.defaultMode.rawValue)
        defer {
            IOHIDDeviceUnscheduleFromRunLoop(device,loop,CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device,0)
            buffer.deallocate()
        }
        let firstID=Int.random(in:1...1_000_000_000)
        let commands=try frame.palette.commands(states:frame.states,selected:frame.selected,firstID:firstID,firmwareSlot:frame.firmwareSlot)
        for (index, packets) in commands.prefix(frame.includeAmbient ? 2 : 1).enumerated() {
            receiver.waiting=firstID+index
            receiver.accepted=nil
            for packet in packets {
                let result=packet.withUnsafeBufferPointer { IOHIDDeviceSetReport(device,kIOHIDReportTypeOutput,6,$0.baseAddress!,64) }
                guard result==0 else { throw CompanionError("조명 전송 실패") }
            }
            let deadline=ProcessInfo.processInfo.systemUptime+1
            while receiver.accepted == nil && ProcessInfo.processInfo.systemUptime < deadline {
                CFRunLoopRunInMode(.defaultMode,0.04,true)
            }
            guard receiver.accepted == true else { throw CompanionError(receiver.accepted == nil ? "조명 응답 시간 초과" : "기기가 조명 설정을 거부했습니다") }
        }
    }
}
