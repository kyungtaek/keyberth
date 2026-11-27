import AppKit
import MicroCore

enum MacActions {
    static let targets: [String:(profile:AppProfile, mic:Bool)] = [
        "target.codex.mic":(.codex,true), "target.t3.mic":(.t3,true), "target.claude.mic":(.claude,true),
        "target.codex.new":(.codex,false), "target.t3.new":(.t3,false), "target.claude.new":(.claude,false),
        "target.cmux.new":(.cmux,false)
    ]
    static let targetLabels = targets.mapValues { target in
        target.profile.title + " · " + (target.mic ? "누르고 받아쓰기" : target.profile == .cmux ? "새 워크스페이스" : "새 대화")
    }
    static let system = [
        "system.scrollUp":"마우스 휠 위로 스크롤", "system.scrollDown":"마우스 휠 아래로 스크롤",
        "system.pageUp":"페이지 업", "system.pageDown":"페이지 다운",
        "apps.nextFavorite":"다음 즐겨찾기 앱", "apps.previousFavorite":"이전 즐겨찾기 앱",
        "system.screenshot":"스크린샷 · 영역 선택", "system.sleep":"Mac 잠자기",
        "system.missionControl":"미션 컨트롤", "system.volumeUp":"볼륨 올리기",
        "system.volumeDown":"볼륨 내리기", "system.mute":"음소거 전환",
        "system.fullScreen":"전체 화면 전환", "system.maximize":"창 최대화",
        "system.left":"창을 왼쪽 절반으로", "system.right":"창을 오른쪽 절반으로",
        "system.nextDisplay":"창을 다음 디스플레이로", "system.playPause":"재생 / 일시 정지",
        "system.nextTrack":"다음 트랙", "system.previousTrack":"이전 트랙"
    ]
    static func appID(_ binding:String) -> String? {
        guard binding.hasPrefix("launch."), case let .application(id)? = AppProfile(rawValue:"app."+binding.dropFirst(7)) else { return nil }
        return id
    }
    static var favorites:[String:String] {
        get { KeyMap.preferences.dictionary(forKey:"favoriteApplications") as? [String:String] ?? [:] }
        set { KeyMap.preferences.set(newValue,forKey:"favoriteApplications") }
    }
    static func runningApps() -> [String:String] {
        var apps = [String:String]()
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let id = app.bundleIdentifier, let name = app.localizedName { apps[id] = name }
        }
        return apps
    }
    static func register(path:String?, id:String?) throws {
        let url = path.map(URL.init(fileURLWithPath:)) ?? id.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier:$0) }
        guard let url, url.pathExtension == "app", let bundle = Bundle(url:url), let id = bundle.bundleIdentifier,
              appID("launch."+id) != nil else { throw CompanionError("응용 프로그램을 선택하세요.") }
        favorites[id] = FileManager.default.displayName(atPath:url.path).replacingOccurrences(of:".app",with:"")
    }
    @MainActor static func launch(_ id:String) async throws {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier:id).first,
           app.activate(options:[]) { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier:id) else { throw CompanionError("설치된 앱을 찾을 수 없습니다 · "+id) }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        _ = try await NSWorkspace.shared.openApplication(at:url,configuration:config)
    }
    static func adjacentFavorite(forward:Bool, current:String?, apps:[String:String]) -> String? {
        let ordered = apps.keys.sorted { a,b in
            let order = apps[a]!.localizedStandardCompare(apps[b]!)
            return order == .orderedSame ? a < b : order == .orderedAscending
        }
        guard let current, let index = ordered.firstIndex(of:current) else {
            return forward ? ordered.first : ordered.last
        }
        return ordered[(index + (forward ? 1 : ordered.count - 1)) % ordered.count]
    }
    @MainActor static func perform(_ action:String) throws {
        if action == "system.scrollUp" || action == "system.scrollDown" {
            guard CGPreflightPostEventAccess() else { throw CompanionError("손쉬운 사용 권한이 필요합니다.") }
            guard let event = CGEvent(scrollWheelEvent2Source:nil,units:.line,wheelCount:1,
                                      wheel1:action == "system.scrollUp" ? 1 : -1,wheel2:0,wheel3:0) else {
                throw CompanionError("스크롤 입력을 만들 수 없습니다.")
            }
            event.post(tap:.cghidEventTap)
            return
        }
        if action == "system.pageUp" || action == "system.pageDown" {
            guard let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                  let profile = AppProfile(rawValue:"app."+bundle) else { throw CompanionError("현재 앱을 확인하세요.") }
            try DesktopShortcut.send(action == "system.pageUp" ? "pageup" : "pagedown",to:profile)
            return
        }
        if action == "system.sleep" {
            _ = try CmuxClient.run(["sleepnow"],executable:"/usr/bin/pmset")
            return
        }
        if action == "system.screenshot" {
            guard CGPreflightPostEventAccess() else { throw CompanionError("손쉬운 사용 권한이 필요합니다.") }
            let hotkeys = UserDefaults.standard.persistentDomain(forName:"com.apple.symbolichotkeys")?["AppleSymbolicHotKeys"] as? [String:Any]
            let shortcut = hotkeys?["30"] as? [String:Any]
            guard shortcut?["enabled"] as? Bool != false else { throw CompanionError("macOS 키보드 설정에서 영역 스크린샷 단축키를 켜세요.") }
            let parameters = (shortcut?["value"] as? [String:Any])?["parameters"] as? [Int]
            let values = parameters ?? [52,21,Int(CGEventFlags([.maskCommand,.maskShift]).rawValue)]
            guard values.count == 3, let code = UInt16(exactly:values[1]), code < 128, values[2] >= 0,
                  let down=CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:true),
                  let up=CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:false) else { throw CompanionError("스크린샷 단축키를 확인하세요.") }
            down.flags=CGEventFlags(rawValue:UInt64(values[2]))
            up.flags=down.flags
            down.post(tap:.cghidEventTap)
            up.post(tap:.cghidEventTap)
            return
        }
        if action == "system.missionControl" {
            guard NSWorkspace.shared.open(URL(fileURLWithPath:"/System/Applications/Mission Control.app")) else { throw CompanionError("미션 컨트롤을 열 수 없습니다.") }
            return
        }
        // macOS consumer media keys use a system-defined down/up event pair.
        let mediaKeys = [
            "system.volumeUp":0, "system.volumeDown":1, "system.mute":7,
            "system.playPause":16, "system.nextTrack":17, "system.previousTrack":18
        ]
        if let key = mediaKeys[action] {
            guard CGPreflightPostEventAccess() else { throw CompanionError("손쉬운 사용 권한이 필요합니다.") }
            for phase in [0xA,0xB] {
                guard let event = NSEvent.otherEvent(with:.systemDefined,location:.zero,modifierFlags:[],
                    timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:0,context:nil,subtype:8,
                    data1:key << 16 | phase << 8,data2:-1)?.cgEvent else { throw CompanionError("미디어 키를 전송할 수 없습니다.") }
                event.post(tap:.cghidEventTap)
            }
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              let window = AppNode(element:AXUIElementCreateApplication(app.processIdentifier)).node("AXFocusedWindow") else { throw CompanionError("이동할 창을 확인하세요.") }
        let failure = CompanionError("이 창에서 해당 동작을 사용할 수 없습니다.")
        if action == "system.fullScreen" {
            guard let full = window.attr("AXFullScreen") as? Bool,
                  AXUIElementSetAttributeValue(window.element,"AXFullScreen" as CFString,!full as CFBoolean) == .success else { throw failure }
            return
        }
        let screens = NSScreen.screens
        guard let top = screens.first?.frame.maxY,
              let point = window.attr("AXPosition"), CFGetTypeID(point)==AXValueGetTypeID(),
              let dimensions = window.attr("AXSize"), CFGetTypeID(dimensions)==AXValueGetTypeID() else { throw failure }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(point as! AXValue,.cgPoint,&origin), AXValueGetValue(dimensions as! AXValue,.cgSize,&size) else { throw failure }
        let current = CGRect(x:origin.x,y:top-origin.y-size.height,width:size.width,height:size.height)
        func overlap(_ screen:NSScreen) -> CGFloat {
            let part = current.intersection(screen.frame)
            return part.isNull ? 0 : part.width * part.height
        }
        guard let index = screens.indices.max(by:{ overlap(screens[$0]) < overlap(screens[$1]) }) else { throw failure }
        var frame = screens[index].visibleFrame
        switch action {
        case "system.maximize": break
        case "system.left","system.right":
            frame.size.width /= 2
            if action == "system.right" { frame.origin.x += frame.width }
        case "system.nextDisplay":
            guard screens.count > 1 else { throw CompanionError("연결된 디스플레이가 하나입니다.") }
            let target = screens[(index+1)%screens.count].visibleFrame
            frame.size = CGSize(width:min(size.width,target.width), height:min(size.height,target.height))
            frame.origin = CGPoint(x:target.midX-frame.width/2,y:target.midY-frame.height/2)
        default: throw failure
        }
        origin = CGPoint(x:frame.minX,y:top-frame.maxY)
        size = frame.size
        guard let p = AXValueCreate(.cgPoint,&origin), let s = AXValueCreate(.cgSize,&size),
              AXUIElementSetAttributeValue(window.element,"AXPosition" as CFString,p) == .success,
              AXUIElementSetAttributeValue(window.element,"AXSize" as CFString,s) == .success,
              AXUIElementSetAttributeValue(window.element,"AXPosition" as CFString,p) == .success else { throw failure }
    }
}
