import AppKit
import MicroCore

enum DesktopShortcut {
    // macOS virtual key codes for the ANSI shortcut key positions.
    static let codes: [String:CGKeyCode] = [
        "a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,
        "q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,
        "6":22,"5":23,"9":25,"7":26,"8":28,"0":29,"o":31,"u":32,"i":34,"p":35,
        "=":24,"-":27,"[":33,"]":30,"enter":36,"l":37,"j":38,"k":40,"n":45,"m":46,"tab":48,"space":49,"backspace":51,
        "escape":53,"f5":96,"f6":97,"f7":98,"f3":99,"f8":100,"f9":101,"f11":103,
        "f10":109,"f12":111,"home":115,"delete":117,"f4":118,"end":119,"f2":120,"f1":122,
        "left":123,"right":124,"down":125,"up":126
    ]
    static let flags: [String:CGEventFlags] = ["cmd":.maskCommand, "ctrl":.maskControl, "alt":.maskAlternate, "shift":.maskShift]
    static func valid(_ chord: String) -> Bool {
        let parts = chord.components(separatedBy: "+")
        let modifiers = parts.dropLast()
        return parts.last.flatMap { codes[$0] } != nil && modifiers.allSatisfy { flags[$0] != nil } && Set(modifiers).count == modifiers.count
    }

    @MainActor static func send(_ chord: String, to profile: AppProfile) throws {
        guard valid(chord), let last = chord.components(separatedBy: "+").last, let code = codes[last] else {
            throw CompanionError("사용할 수 없는 단축키입니다.")
        }
        let front = NSWorkspace.shared.frontmostApplication
        let target = [front].compactMap { $0 }.first { profile.bundleIDs.contains($0.bundleIdentifier ?? "") }
            ?? profile.bundleIDs.lazy.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }.first
        guard let target, !target.isTerminated else { throw CompanionError(profile.title + " 앱을 먼저 열어 주세요.") }
        guard CGPreflightPostEventAccess() else {
            throw CompanionError("macOS 손쉬운 사용에서 Keyberth의 키 입력 권한이 필요합니다.")
        }
        guard let down = CGEvent(keyboardEventSource:nil, virtualKey:code, keyDown:true),
              let up = CGEvent(keyboardEventSource:nil, virtualKey:code, keyDown:false) else {
            throw CompanionError("키 이벤트를 만들 수 없습니다.")
        }
        let modifiers = chord.components(separatedBy:"+").dropLast().reduce(CGEventFlags()) { $0.union(flags[$1]!) }
        down.flags = modifiers
        up.flags = modifiers
        down.postToPid(target.processIdentifier)
        up.postToPid(target.processIdentifier)
    }
}
