import AppKit
import MicroCore

@main struct MicroCompanion {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--claude-hook") { try? ClaudeCodeHook.run(); return }
        if CommandLine.arguments.contains("--check-device") {
            do {
                let (location, version) = try AgentDevice.connection()
                if location != nil { print("USB CDC: " + version) }
                var reply: String?
                let hid = try AgentHID(location: location, expectedVersion:version, status: { reply = $0 }, press: { _ in })
                let deadline = Date().addingTimeInterval(8)
                while reply == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
                hid.close()
                guard let reply, reply.contains(" 연결됨 · ") else { throw CompanionError(reply ?? "USB HID 응답 시간 초과") }
                print(reply)
                exit(0)
            } catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
        }

        let model = Companion()
        model.start()
        DispatchQueue.global().async {
            while let line = readLine() {
                let request = Data(line.utf8)
                DispatchQueue.main.async { Task { await model.respond(request) } }
            }
            DispatchQueue.main.async { model.stop(); exit(0) }
        }
        RunLoop.main.run()
    }
}

@MainActor final class Companion {
    var deviceStatus = "USB 확인 대기"
    var cmuxStatus = "cmux 확인 대기"
    var rows = [CmuxTarget?](repeating: nil, count: 6)
    var lights = Array(repeating: SessionLight.empty, count: 6)
    private var cmuxMappings = KeyMap.savedMaps?["cmux"] ?? KeyMap.load()
    private var profiles = KeyMap.savedMaps?.filter { $0.key != "cmux" } ?? (KeyMap.preferences.dictionary(forKey: "desktopKeyMaps") as? [String:[String:String]] ?? [:])
    private var profile = AppProfile(rawValue: KeyMap.preferences.string(forKey: "selectedKeyMap") ?? "") ?? .cmux
    private var enabled = KeyMap.preferences.stringArray(forKey:"enabledAppProfiles")?.compactMap(AppProfile.init(rawValue:)).filter(\.selectable) ?? AppProfile.initial
    private func title(_ p:AppProfile) -> String {
        if case .application(let bundle) = p, let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:bundle) { return url.deletingPathExtension().lastPathComponent }
        return p == .unconfigured ? "글로벌" : p.title
    }
    private var profileList:[[String:String]] { enabled.map { ["id":$0.rawValue,"name":title($0)] } }
    private func storeEnabled() { KeyMap.preferences.set(enabled.map(\.rawValue),forKey:"enabledAppProfiles") }
    private var automatic = (KeyMap.preferences.object(forKey:"automaticKeyMap") as? Bool) ?? true
    private let appSwitchHUD = AppSwitchHUDSetting(preferences: KeyMap.preferences)
    private var wakeObserver: NSObjectProtocol?
    private var focusObserver: NSObjectProtocol?
    var feedback = ""

    private func hud(_ subtitle: String, changes:[[String:String]] = [], fromAppSwitch: Bool = false) {
        let event:[String:Any] = ["event":"hud", "title":title(profile), "subtitle":subtitle, "keys":changes, "fromAppSwitch":fromAppSwitch]
        if var bytes = try? JSONSerialization.data(withJSONObject:event) {
            bytes.append(10)
            FileHandle.standardOutput.write(bytes)
        }
    }
    private func activate(_ next: AppProfile, trigger: AppSwitchHUDSetting.Trigger = .manual) {
        guard next != profile else { return }
        if micProfile != next { finishMic() }
        selectedClaudeCode = nil
        visibleDesktop = nil
        if profile == .claudeCode { ClaudeCodeHook.endLease() }
        if next == .claude || next == .claudeCode { KeyMap.preferences.set(next.rawValue, forKey:"preferredClaudeProfile") }
        if profile == .slack { slackQueue.removeAll(); slackTask?.cancel(); SlackDesktop.clearSlots() }
        let previous = profile
        if profile.hasRecentSessions { backgroundSessions[profile]=sessions.compactMap{$0} }
        profile = next
        sessionStatus = next.title
        sessionGeneration = UUID()
        sessions = (backgroundSessions[next] ?? []).map { $0 }
        updateLights()
        refreshDesktop()
        KeyMap.preferences.set(next.rawValue, forKey:"selectedKeyMap")
        if appSwitchHUD.allows(trigger) {
            let changes = KeyMap.controls.compactMap { key -> [String:String]? in
                let value = binding(key,in:next)
                let old = binding(key,in:previous)
                guard value != old || next.agentActions[value] != previous.agentActions[old] ||
                    (recentIndex(value) != nil && previous != next) else { return nil }
                let label = next.agentActions[value] ?? MacActions.targetLabels[value] ?? MacActions.system[value] ?? ApplicationMenu.path(value)?.last ??
                    MacActions.appID(value).map { MacActions.favorites[$0] ?? $0 } ?? (value == "none" ? "미할당" : KeyMap.label(value))
                let name = commonIndex(value).map { "통합 최근 세션 "+String($0+1) } ?? ObsidianNote.path(value).map { URL(fileURLWithPath:$0).deletingPathExtension().lastPathComponent } ?? label
                return ["key":key,"name":name]
            }
            if !changes.isEmpty { hud("키맵 전환", changes:changes, fromAppSwitch:trigger == .appSwitch) }
        }
    }
    private func follow(_ bundle: String?, trigger: AppSwitchHUDSetting.Trigger = .appSwitch) {
        guard automatic, let bundle else { return }
        if AppProfile.claude.bundleIDs.contains(bundle), enabled.contains(.claudeCode),
           !enabled.contains(.claude) || KeyMap.preferences.string(forKey:"preferredClaudeProfile") == AppProfile.claudeCode.rawValue {
            activate(.claudeCode,trigger:trigger)
        } else if let next = enabled.first(where: { $0.bundleIDs.contains(bundle) }) {
            activate(next,trigger:trigger)
        } else if !["local.kent.microcmux","com.github.Electron"].contains(bundle) {
            activate(.unconfigured,trigger:trigger)
        }
    }
    private func toggleAutomatic() {
        automatic.toggle()
        KeyMap.preferences.set(automatic, forKey:"automaticKeyMap")
        follow(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, trigger:.silent)
        hud(automatic ? "자동 전환 켬" : "자동 전환 끔")
    }
    private var global = KeyMap.preferences.dictionary(forKey:"globalBindings") as? [String:String] ?? [:]
    private func commonIndex(_ value:String) -> Int? {
        (1...6).first { value == "allRecent."+String($0) }.map { $0-1 }
    }
    private func globalDefault(_ key:String) -> String {
        guard let index=KeyMap.keys.prefix(6).firstIndex(of:key) else { return "none" }
        return "allRecent."+String(index+1)
    }
    private func localValue(_ key:String, _ p:AppProfile) -> String? {
        KeyMap.localBinding(p == .cmux ? cmuxMappings[key] : profiles[p.rawValue]?[key])
    }
    private func binding(_ key:String, in p:AppProfile) -> String {
        localValue(key,p) ?? global[key] ?? globalDefault(key)
    }
    private func save(_ value:String, for input:String, in p:AppProfile) {
        if p == .cmux { cmuxMappings[input] = value }
        else { profiles[p.rawValue,default:[:]][input] = value }
        KeyMap.preferences.set(exportMaps,forKey:"keymapOverridesV1")
    }
    private var exportMaps: [String:[String:String]] {
        Dictionary(uniqueKeysWithValues:enabled.map { ($0.rawValue,$0 == .cmux ? cmuxMappings : profiles[$0.rawValue] ?? [:]) })
    }
    private let cmuxSpace = CmuxSpace()
    private var micProfile: AppProfile?
    private var t3Dictation: T3Controls.Dictation?
    private var codexDictation: CodexControls.Dictation?
    private var codexPickerTask: Task<Void,Never>?
    private var codexForkPending = false
    private var targetPresses = [String:UUID]()
    private var launchingOrcaCodex = false
    private var micKeys = Set<String>()
    private var releaseOrcaDictation: (() -> Void)?
    private func finishMic() {
        cmuxSpace.cancel()
        guard let held = micProfile else { return }
        micProfile = nil
        micKeys.removeAll()
        do {
            if let release = releaseOrcaDictation { releaseOrcaDictation=nil; release(); return }
            if let hold = t3Dictation {
                t3Dictation = nil
                try hold.finish()
                return
            }
            if let hold = codexDictation {
                codexDictation = nil
                try CodexControls.endDictation(hold)
                return
            }
            try ClaudeControls.press(["stop dictation","finish dictation","starting dictation; click to cancel","받아쓰기 종료","받아쓰기 중지","받아쓰기 중단"],in:held)
        } catch { feedback = error.localizedDescription; hud(feedback) }
    }
    private func release(_ physical: DeckInput) {
        targetPresses.removeValue(forKey:KeyMap.code(physical))
        cmuxSpace.release(KeyMap.code(physical))
        guard micKeys.remove(KeyMap.code(physical)) != nil, micKeys.isEmpty else { return }
        finishMic()
    }
    private var selectedClaudeCode: URL? { didSet { if selectedClaudeCode != oldValue { selectedRequest = nil } } }
    private var t3HighWater = KeyMap.preferences.double(forKey:"t3CompletionWatermark")
    private var completions = CompletionIndicator()
    private func indicator(_ item:DesktopSession, source:AppProfile, now:Double) -> DesktopSession {
        device?.observeSession(source.rawValue+"/"+item.url.absoluteString,item.light,revision:item.completionRevision)
        var result = item
        let previous = activity.entries[source.rawValue+"/"+item.url.absoluteString]
        let newlyCompleted = source == .t3 && item.light == .done && (
            (previous == nil && t3HighWater > 0 && item.updated > t3HighWater) ||
            (previous != nil && (previous?.state == SessionLight.running.rawValue ||
             previous?.state == SessionLight.attention.rawValue || (previous?.revision != nil && previous?.revision != item.completionRevision))))
        result.updated = activity.observe(id:source.rawValue+"/"+item.url.absoluteString, light:item.light, revision:item.completionRevision, initialTime:item.updated, workTime:source == .codex || source == .t3 ? item.updated : nil, now:now)
        result.light = completions.display(item.light, id:item.url.absoluteString, revision:item.completionRevision, newlyCompleted:newlyCompleted)
        return result
    }
    private func rankedSessions(_ items:[DesktopSession],source:AppProfile) -> [DesktopSession] {
        let now = Date().timeIntervalSince1970
        let observed = items.map { indicator($0,source:source,now:now) }
        if source == .t3 {
            let watermark = max(t3HighWater,items.map(\.updated).max() ?? 0)
            if watermark > t3HighWater || t3HighWater == 0 {
                t3HighWater = watermark > 0 ? watermark : now
                KeyMap.preferences.set(t3HighWater,forKey:"t3CompletionWatermark")
            }
        }
        return observed.sorted { a,b in
            a.updated == b.updated ? a.url.absoluteString < b.url.absoluteString : a.updated > b.updated
        }
    }
    private var selectedRequest: String?
    private var claudeCatalog = [ClaudeCodeSessions.Session]()
    private var claudeSource = KeyMap.preferences.string(forKey:"claudeSessionSource") ?? ""
    private var claudePins = KeyMap.preferences.dictionary(forKey:"claudeSlotPins") as? [String:String] ?? [:]
    private var sourceSessions: [ClaudeCodeSessions.Session] { claudeCatalog.filter { claudeSource.isEmpty || $0.source == claudeSource } }
    private func rebuildClaudeSlots() {
        let items = sourceSessions
        let ranked = rankedSessions(items.map { session in
            var row = session.item
            row.updated = session.updated / 1000
            return row
        },source:.claudeCode)
        var remaining = ranked.filter { !claudePins.values.contains($0.url.absoluteString) }.makeIterator()
        sessions = (1...6).map { slot in
            if let pin=claudePins[String(slot)] { return ranked.first { $0.url.absoluteString == pin } }
            return remaining.next()
        }
        if !items.contains(where:{$0.item.url == selectedClaudeCode}) { selectedClaudeCode = nil }
        sessionStatus = profile.title + " · 슬롯 " + String(sessions.compactMap{$0}.count) + "/6"
        updateLights()
    }
    private func claudeOptions() -> [String:Any] {
        guard profile == .claudeCode else { return [:] }
        let requests = sourceSessions.first(where:{$0.item.url == selectedClaudeCode}).map { ClaudeCodeHook.requests($0.cli) } ?? []
        return ["source":claudeSource, "sources":Array(Set(claudeCatalog.map(\.source))).sorted(), "pins":claudePins,
                "choices":sourceSessions.map { ["id":$0.item.url.absoluteString,"name":$0.item.title] },
                "request":selectedRequest ?? "", "requests":requests.sorted(by:{$0.lastPathComponent<$1.lastPathComponent}).map {
                    ["id":$0.lastPathComponent,"name":(try? String(contentsOf:$0.appendingPathComponent("tool"),encoding:.utf8)) ?? "권한 요청"]
                }]
    }
    private func openSession(_ item:DesktopSession, source:AppProfile) async throws {
        try await DesktopSessions.open(item,profile:source)
        completions.markViewed(item.url.absoluteString)
        if profile == source, let index = sessions.firstIndex(where:{$0?.url == item.url}), sessions[index]?.light == .done {
            sessions[index]?.light = .ready
            updateLights()
        }
        if source == .claudeCode, profile == source { selectedClaudeCode = item.url; updateLights() }
    }
    private var sessions = [DesktopSession?]()
    private var visibleDesktop: URL?
    private var selectedSession: URL? {
        profile == .claudeCode ? selectedClaudeCode : visibleDesktop
    }
    private var sessionGeneration = UUID()
    private var pendingGeneration: UUID?
    private var sessionStatus = ""
    private func refreshDesktop() {
        guard profile.hasRecentSessions, pendingGeneration != sessionGeneration else { return }
        let generation = sessionGeneration, source = profile
        pendingGeneration = generation
        Task {
            do {
                if source == .claudeCode {
                    let catalog = await Task.detached { ClaudeCodeSessions.read() }.value
                    guard generation == sessionGeneration else { return }
                    claudeCatalog = catalog
                    rebuildClaudeSlots()
                    pendingGeneration = nil
                    return
                }
                let items = try await Task.detached { try DesktopSessions.read(source) }.value
                guard generation == sessionGeneration else { return }
                if source == .codex {
                    visibleDesktop = DesktopSessions.visibleCodexSession(in:items)
                    if let visibleDesktop, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == source.bundleIDs.first {
                        completions.markViewed(visibleDesktop.absoluteString)
                    }
                }
                if source == .t3 {
                    visibleDesktop = T3Controls.visibleRoute().flatMap { route in
                        items.first { T3Navigation.matchesVisibleRoute(route,threadURL:$0.url) }?.url
                    }
                }
                sessions = rankedSessions(items,source:source)
                sessionStatus = source.title + " · 슬롯 " + String(items.count) + "/6"
            } catch {
                guard generation == sessionGeneration else { return }
                visibleDesktop = nil
                sessions = []
                sessionStatus = source.title + " · " + error.localizedDescription
            }
            pendingGeneration = nil
            updateLights()
        }
    }
    private var palette: SessionLighting? = {
        guard let data = KeyMap.preferences.data(forKey:"sessionLighting"),
              let saved = try? JSONDecoder().decode(SessionLighting.self,from:data), saved.valid else { return nil }
        if KeyMap.preferences.integer(forKey:"slotPaletteVersion") < 2 {
            let migrated = saved.migratingLegacySlotColors
            if let data = try? JSONEncoder().encode(migrated) {
                KeyMap.preferences.set(data,forKey:"sessionLighting")
                KeyMap.preferences.set(2,forKey:"slotPaletteVersion")
            }
            return migrated
        }
        return saved
    }()
    private var slotPalette: SessionLighting? {
        guard profile == .t3, let palette, let empty = palette.rules[SessionLight.empty.rawValue] else { return palette }
        var rules = palette.rules
        rules[SessionLight.empty.rawValue] = .init(slot:.init(color:empty.slot.color,effect:0),ambient:empty.ambient)
        return SessionLighting(rules:rules)
    }
    private struct CombinedSlot {
        let source:AppProfile
        let item:DesktopSession
        var surface:CmuxTarget? = nil
        var id:String { source.rawValue+"/"+(surface?.id.uuidString ?? item.url.absoluteString) }
    }
    private var backgroundSessions = [AppProfile:[DesktopSession]]()
    private var collecting = false
    private var activity = SessionActivity(entries: (KeyMap.preferences.data(forKey:"sessionActivityV1").flatMap {
        try? JSONDecoder().decode([String:SessionActivity.Entry].self,from:$0)
    }) ?? [:])
    private var persistedActivity: [String:SessionActivity.Entry]?
    private func persistActivity() {
        guard persistedActivity != activity.entries, let data=try? JSONEncoder().encode(activity.entries) else { return }
        persistedActivity=activity.entries
        KeyMap.preferences.set(data,forKey:"sessionActivityV1")
    }
    private func refreshCombined() {
        guard !collecting else { return }
        collecting=true
        let sources=enabled.filter { $0.hasRecentSessions && $0 != profile }
        Task {
            let items = await Task.detached {
                var result=[AppProfile:[DesktopSession]]()
                for source in sources {
                    if source == .claudeCode {
                        result[source]=ClaudeCodeSessions.read().map { session in
                            var item=session.item; item.updated=session.updated/1000; return item
                        }
                    } else { result[source]=(try? DesktopSessions.read(source)) ?? [] }
                }
                return result
            }.value
            for (source,items) in items where source != profile {
                backgroundSessions[source]=Array(rankedSessions(items,source:source).prefix(6))
            }
            collecting=false
            updateLights()
        }
    }
    private var combined:[CombinedSlot] {
        var result=[CombinedSlot]()
        for source in enabled where source.hasRecentSessions {
            let items = source == profile ? sessions.compactMap{$0} : backgroundSessions[source] ?? []
            for item in items {
                result.append(CombinedSlot(source:source,item:item))
            }
        }
        if enabled.contains(.cmux) {
            for (index,row) in rows.enumerated() {
                guard let row else { continue }
                let item=DesktopSession(url:URL(fileURLWithPath:row.id.uuidString),title:row.title,light:lights[index],updated:activity.entries["cmux/"+row.id.uuidString]?.time ?? 0)
                result.append(CombinedSlot(source:.cmux,item:item,surface:row))
            }
        }
        return Array(result.sorted { a,b in
            a.item.updated == b.item.updated ? a.id < b.id : a.item.updated > b.item.updated
        }.prefix(6))
    }
    private func openCombined(_ slot:CombinedSlot) async throws {
        if let surface=slot.surface {
            try await Task.detached { try CmuxClient.focus(surface) }.value
        } else { try await openSession(slot.item,source:slot.source) }
        updateLights()
    }
    private func combinedRow(_ slot:CombinedSlot) -> [String:Any] {
        let light=slot.item.light
        return ["target":"combined:"+slot.id,"title":title(slot.source)+" · "+slot.item.title,
                "active":slot.source==profile && (slot.surface?.active ?? (selectedSession==slot.item.url)),
                "state":light.rawValue,"led":light.agentCode,"lightColor":(palette ?? .initial).rules[light.rawValue]?.slot.color ?? ""]
    }
    private func updateLights() {
        persistActivity()
        let shared=combined
        var selected:Int?
        let states:[SessionLight]=KeyMap.keys.prefix(6).enumerated().map { position,key in
            let value=binding(key,in:profile)
            if let i=commonIndex(value), shared.indices.contains(i) {
                let slot=shared[i]
                if slot.source==profile && (slot.surface?.active ?? (slot.item.url==selectedSession)) { selected=position }
                return slot.item.light
            }
            if profile == .cmux, let i=KeyMap.keys.prefix(6).firstIndex(of:value) {
                if rows[i]?.active == true { selected=position }
                return lights[i]
            }
            if let i=recentIndex(value), sessions.indices.contains(i), let item=sessions[i] {
                if item.url==selectedSession { selected=position }
                return item.light
            }
            return .empty
        }
        let style=slotPalette
        let breathing=(style ?? .initial).breathingSlot(states:states,viewed:selected)
        device?.display(states,selected:selected,palette:style,firmwareSlot:breathing)
    }
    private func recentIndex(_ value:String) -> Int? { (1...6).first { value == "recent."+String($0) }.map { $0-1 } }
    private var queue: [(DeckInput, CmuxTarget?, String?)] = []
    private func handle(_ physical: DeckInput) {
        let code = KeyMap.code(physical)
        // Rotation is a detent, so a held binding must finish within this event.
        defer { if case .turn = physical { release(physical) } }

        let binding = binding(code, in:profile)
        if let index = commonIndex(binding) {
            let combined=self.combined
            guard combined.indices.contains(index) else { hud("빈 세션 슬롯"); return }
            let slot = combined[index]
            let diagnostics=CommandLine.arguments.contains("--agent-diagnostics")
            if diagnostics { fputs("slot "+code+" "+slot.id+" "+slot.item.light.rawValue+"\n",stderr) }
            Task {
                do {
                    try await openCombined(slot)
                    if diagnostics {
                        try await Task.sleep(nanoseconds:650_000_000)
                        let front=NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
                        var visible:String?
                        if slot.source == .cmux { visible=try? CmuxClient.focusedID().uuidString }
                        else if slot.source == .codex { visible=DesktopSessions.visibleCodexSession(in:[slot.item])?.absoluteString }
                        else if slot.source == .t3 { visible=T3Controls.visibleRoute()?.absoluteString }
                        fputs("opened "+code+" "+front+" "+(visible ?? "unknown")+"\n",stderr)
                    }
                } catch { hud(error.localizedDescription) }
            }
            return
        }
        if localValue(code,profile) == nil, DesktopShortcut.valid(binding),
           let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            do { try DesktopShortcut.send(binding,to:.application(id)) } catch { hud(error.localizedDescription) }
            return
        }
        if binding == "none" { return }
        if let target = MacActions.targets[binding], let bundle = target.profile.bundleIDs.first {
            let token = UUID()
            if target.mic { targetPresses[code] = token }
            Task {
                defer { if targetPresses[code] == token { targetPresses.removeValue(forKey:code) } }
                do {
                    try await MacActions.launch(bundle)
                    let deadline = ProcessInfo.processInfo.systemUptime + 12
                    while true {
                        if target.mic && targetPresses[code] != token { return }
                        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundle,
                           let app=NSRunningApplication.runningApplications(withBundleIdentifier:bundle).first {
                            let root=AppNode(element:AXUIElementCreateApplication(app.processIdentifier))
                            AXUIElementSetAttributeValue(root.element,"AXManualAccessibility" as CFString,kCFBooleanTrue)
                            if let window=root.node("AXFocusedWindow") {
                                if target.profile == .cmux { break }
                                let ready=window.descendants({ node in
                                    if !target.mic { return node.role == "AXWebArea" }
                                    if target.profile == .claude {
                                        return node.role == "AXButton" && ["start dictation","dictate","받아쓰기 시작","받아쓰기"].contains(ClaudeControls.label(node).lowercased())
                                    }
                                    return node.role == "AXTextArea" && node.identifier.contains(target.profile == .t3 ? "composer-tiptap" : "prosemirror")
                                },first:true)
                                if !ready.isEmpty { break }
                            }
                        }
                        guard ProcessInfo.processInfo.systemUptime < deadline else { throw CompanionError("대상 앱의 창을 열 수 없습니다.") }
                        try await Task.sleep(nanoseconds:150_000_000)
                    }
                    if target.mic {
                        guard micProfile == nil else { return }
                        switch target.profile {
                        case .t3: t3Dictation = try T3Controls.startDictation()
                        case .codex: codexDictation = try CodexControls.startDictation()
                        default: try AssistantControls.perform("agent.mic",in:target.profile)
                        }
                        micProfile = target.profile
                        micKeys.insert(code)
                    } else if target.profile == .cmux {
                        _ = try CmuxClient.run(["new-workspace","--focus","true"])
                    } else if target.profile == .t3 {
                        try await T3Controls.perform("agent.newChat",stillActive:{ NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundle })
                    } else { try AssistantControls.perform("agent.newChat",in:target.profile) }
                } catch { hud(error.localizedDescription) }
            }
            return
        }
        if binding == "apps.nextFavorite" || binding == "apps.previousFavorite" {
            guard let id = MacActions.adjacentFavorite(forward:binding == "apps.nextFavorite",
                current:NSWorkspace.shared.frontmostApplication?.bundleIdentifier,apps:MacActions.favorites) else {
                hud("기기 설정에서 전환할 앱을 즐겨찾기에 추가하세요.")
                return
            }
            Task {
                do { try await MacActions.launch(id); feedback = "" }
                catch { feedback = error.localizedDescription; hud(feedback) }
            }
            return
        }
        if let id = MacActions.appID(binding) {
            Task {
                do { try await MacActions.launch(id); feedback = "" }
                catch { feedback = error.localizedDescription; hud(feedback) }
            }
            return
        }
        if MacActions.system[binding] != nil || ApplicationMenu.path(binding) != nil {
            do {
                if let path = ApplicationMenu.path(binding) { try ApplicationMenu.perform(path,profile:profile) }
                else { try MacActions.perform(binding) }
                feedback = ""
            } catch { feedback = error.localizedDescription; hud(feedback) }
            return
        }
        if profile == .cmux, binding == "K11" || binding == "space" {
            cmuxSpace.press(code) { [weak self] in self?.feedback = $0 }
            return
        }
        if profile == .codex || profile == .claude || profile == .claudeCode {
            let target:AppProfile = profile == .codex ? .codex : .claude
            // Session keys may bring Claude forward. Plain shortcuts only go to
            // the intended foreground application, as in the vendor binding table.
            if !binding.hasPrefix("recent."), binding != "agent.dots", !target.bundleIDs.contains(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "") { return }
        }
        if profile != .cmux {
            guard binding != "none" else { return }
            if profile == .slack, let input = SlackAction.input(binding) {
                slackQueue.append(input)
                runSlackActions()
                return
            }
            do {
                if profile == .orca, let action = OrcaCatalog.byBinding[binding] {
                    if action.id == OrcaControls.codexTab {
                        guard !launchingOrcaCodex else { return }
                        launchingOrcaCodex = true
                        Task {
                            defer { launchingOrcaCodex=false }
                            do { try await OrcaControls.launchCodex() }
                            catch { feedback=error.localizedDescription; hud(feedback) }
                        }
                    } else if action.id == "voice.dictation" {
                        if micProfile == nil {
                            releaseOrcaDictation = try OrcaControls.press(action)
                            micProfile = .orca
                        }
                        if micProfile == .orca { micKeys.insert(code) }
                    } else {
                        let release = try OrcaControls.press(action)
                        release()
                    }
                } else if let index = recentIndex(binding), profile.hasRecentSessions {
                    guard sessions.indices.contains(index), let item = sessions[index] else { throw CompanionError("빈 세션 슬롯입니다.") }
                    let source = profile
                    Task {
                        do { try await openSession(item,source:source) }
                        catch { feedback = error.localizedDescription; hud(feedback) }
                    }
                } else if binding.hasPrefix("agent."), profile.agentActions[binding] != nil {
                    if profile == .claudeCode { try ClaudeCodeHook.decide(binding == "agent.approve",for:selectedClaudeCode,requestID:selectedRequest) }
                    else if profile == .t3, binding == "agent.dictate" {
                        if micProfile == nil { t3Dictation = try T3Controls.startDictation(); micProfile = .t3 }
                        micKeys.insert(code)
                    } else if profile == .t3 { performT3(binding) }
                    else if profile == .codex, let step = CodexControls.PickerStep(rawValue:binding) {
                        let previous = codexPickerTask
                        codexPickerTask = Task {
                            await previous?.value
                            guard profile == .codex else { return }
                            do { try await CodexControls.adjust(step) }
                            catch { feedback = error.localizedDescription; hud(feedback) }
                        }
                    }
                    else if profile == .codex, binding == "agent.fork" {
                        guard !codexForkPending else { return }
                        codexForkPending = true
                        Task {
                            defer { codexForkPending = false }
                            do { try await CodexControls.fork() }
                            catch { feedback = error.localizedDescription; hud(feedback) }
                        }
                    } else if binding == "agent.mic" {
                        if micProfile == nil {
                            if profile == .codex { codexDictation = try CodexControls.startDictation() }
                            else { try AssistantControls.perform(binding,in:profile) }
                            micProfile = profile
                        }
                        micKeys.insert(code)
                    } else { try AssistantControls.perform(binding,in:profile) }
                } else if profile == .obsidian, let path = ObsidianNote.path(binding) { try ObsidianNote.open(path) }
                else { try DesktopShortcut.send(binding, to:profile == .claudeCode ? .claude : profile) }
                feedback = ""
            }
            catch { feedback = error.localizedDescription; hud(feedback) }
            return
        }
        if let action = DeckInput(id: binding) {
            guard action != .knobPress else { return }
            enqueue(action)
        }
        else if AppProfile.cmux.agentActions[binding] != nil { enqueue(physical,chord:binding) }
        else if let chord = FunctionKey.shortcut(binding) { enqueue(physical, chord: chord) }
    }
    private var t3Busy = false
    private func performT3(_ action:String) {
        guard !t3Busy else { hud("T3 동작 처리 중"); return }
        let generation=sessionGeneration
        t3Busy = true
        Task {
            defer { t3Busy = false }
            do {
                guard sessionGeneration == generation else { return }
                try await T3Controls.perform(action, stillActive:{ self.sessionGeneration == generation })
                if action == "agent.settle" { sessionGeneration = UUID(); refreshDesktop(); refreshCombined() }
                feedback = ""
            } catch { feedback=error.localizedDescription; hud(feedback) }
        }
    }
    private var slackQueue = [String]()
    private var slackTask:Task<Void,Never>?
    private func runSlackActions() {
        guard slackTask == nil else { return }
        slackTask = Task {
            defer {
                slackTask = nil
                if profile == .slack && !slackQueue.isEmpty { runSlackActions() }
            }
            while profile == .slack && !Task.isCancelled && !slackQueue.isEmpty {
                let input = slackQueue.removeFirst()
                do { try await SlackDesktop.perform(input); feedback = "" }
                catch is CancellationError { return }
                catch { feedback = error.localizedDescription; hud(feedback) }
            }
        }
    }
    private func enqueue(_ input: DeckInput, chord: String? = nil) {
        guard !connecting else { return }
        var target: CmuxTarget?
        if chord == nil, case .key(let number) = input, (1...6).contains(number) {
            guard let slot = rows[number-1] else { return }
            target = slot
        }
        queue.append((input, target, chord))
        drain()
    }
    private func drain() {
        guard !selecting, !queue.isEmpty else { return }
        selecting = true
        Task {
            while !queue.isEmpty {
                let (input, target, override) = queue.removeFirst()
                do {
                    try await Task.detached {
                        if let target { try CmuxClient.focus(target) }
                        else { try await CmuxClient.perform(input, override: override) }
                    }.value
                    feedback = ""
                } catch { feedback = error.localizedDescription }
            }
            selecting = false
            refresh()
        }
    }
    var selecting = false
    var connecting = false
    private var device: AgentHID?
    private var epoch = UUID()
    private var refreshing = false
    private var timer: Timer?
    private var composerTimer: Timer?
    private var checkingComposer = false
    private func refreshComposer() {
        guard let device, device.supportsKeyLighting else { return }
        let source=profile
        let action=binding("K13",in:source)
        guard ["agent.submit","enter"].contains(action), let front=NSWorkspace.shared.frontmostApplication,
              source.bundleIDs.contains(front.bundleIdentifier ?? ""), [.codex,.claude,.t3].contains(source) else {
            device.sendReady=false
            return
        }
        guard !checkingComposer else { return }
        checkingComposer=true
        let pid=front.processIdentifier
        Task {
            let ready=await Task.detached { ComposerAvailability.canSubmit(in:source,pid:pid) }.value
            checkingComposer=false
            guard self.device === device, profile == source, binding("K13",in:source) == action,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            device.sendReady=ready
        }
    }

    func start() {
        if profile != .unconfigured, !enabled.contains(profile) { activate(enabled.first ?? .unconfigured,trigger:.silent) }
        guard timer == nil else { return }
        focusObserver = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification, object:nil, queue:.main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.follow(app?.bundleIdentifier) }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.connect() }
        }
        follow(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, trigger:.silent)
        connect()
        composerTimer = Timer.scheduledTimer(withTimeInterval:0.4,repeats:true) { [weak self] _ in
            Task { @MainActor in self?.refreshComposer() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.device?.stopped != false && !self.connecting { self.connect() }
                else { self.refresh() }
            }
        }
    }
    func stop() {
        targetPresses.removeAll()
        if profile == .claudeCode { ClaudeCodeHook.endLease() }
        finishMic()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver); self.wakeObserver=nil }
        if let focusObserver { NSWorkspace.shared.notificationCenter.removeObserver(focusObserver); self.focusObserver = nil }
        composerTimer?.invalidate()
        composerTimer=nil
        timer?.invalidate()
        timer = nil
        epoch = UUID()
        device?.close()
        device = nil
    }
    func connect() {
        guard !connecting, !selecting else { return }
        targetPresses.removeAll()
        finishMic()
        let token = UUID()
        epoch = token
        connecting = true
        rows = Array(repeating: nil, count: 6)
        device?.close()
        device = nil
        deviceStatus = "USB 펌웨어 확인 중"
        Task { [self] in
            do {
                let (location,version) = try await Task.detached {
                    try AgentDevice.connection()
                }.value
                guard epoch == token else { return }
                deviceStatus = "Universal Agent 세션 연결 중"
                device = try AgentHID(location: location, expectedVersion:version, status: { [weak self] message in
                    if self?.epoch == token { self?.deviceStatus = message; if message.contains("다시 연결") { self?.targetPresses.removeAll(); self?.finishMic() } }
                }, ready: { [weak self] in
                    guard let self, self.epoch == token else { return }
                    self.updateLights()
                    self.refresh()
                    self.refreshComposer()
                }, release: { [weak self] input in self?.release(input) }, press: { [weak self] key in
                    guard self?.epoch == token else { return }
                    self?.handle(key)
                })
            } catch { deviceStatus = error.localizedDescription }
            connecting = false
            updateLights()
            refresh()
        }
    }
    func refresh() {
        if profile == .claudeCode, deviceStatus.contains(" 연결됨 · ") { ClaudeCodeHook.heartbeat() }
        refreshDesktop()
        refreshCombined()
        guard enabled.contains(.cmux) else { return }
        guard !refreshing, !selecting, !connecting else { return }
        let token = epoch
        refreshing = true
        Task {
            defer { refreshing = false }
            do {
                let live = try await Task.detached { try CmuxClient.list() }.value
                guard epoch == token, !selecting else { return }
                let syncBindings = profile == .cmux
                let states = await Task.detached {
                    if syncBindings { CodexBinding.refresh(live) }
                    var signals: [UUID: WorkspaceSignal] = [:]
                    for group in Dictionary(grouping: live, by: \.workspace).values {
                        if let target = group.first { signals[target.workspace] = try? CmuxClient.signal(target) }
                    }
                    return live.map { row -> SessionLight in
                        return signals[row.workspace]?.light(active: row.active) ?? .unknown
                    }
                }.value
                guard epoch == token else { return }
                let cmuxFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == AppProfile.cmux.bundleIDs.first
                let observed=Date().timeIntervalSince1970
                let observations: [(CmuxTarget,SessionLight,Double)] = zip(live,states).map { row,state in
                    device?.observeSession("cmux/"+row.workspace.uuidString,state)
                    return (row,state,activity.observe(id:"cmux/"+row.id.uuidString,light:state,now:observed))
                }
                let ranked = observations.sorted { a,b in a.2 == b.2 ? a.0.id.uuidString < b.0.id.uuidString : a.2 > b.2 }
                rows = (0..<6).map { ranked.indices.contains($0) ? ranked[$0].0 : nil }
                lights = (0..<6).map { index in
                    guard ranked.indices.contains(index) else { return .empty }
                    let (row,state,_) = ranked[index]
                    return completions.display(state,id:row.id.uuidString,viewed:cmuxFront && row.active)
                }
                cmuxStatus = "cmux 연결됨 · 슬롯 \(rows.compactMap { $0 }.count)/6"
            } catch {
                guard epoch == token else { return }
                rows = Array(repeating: nil, count: 6)
                lights = Array(repeating: .empty, count: 6)
                cmuxStatus = "cmux 연결 실패 · \(error.localizedDescription)"
            }
            updateLights()
        }
    }
    private var preferences: DevicePreferences.Snapshot?
    private var preferencesBusy = false

    struct Request: Decodable {
        let id: Int
        let method: String
        let input, binding, target, profile, scope: String?
        let volume, sleep, brightness: Int?
        let styles: [String]?
        let archive: KeymapArchive?
        let revision: UInt32?
        let showAppSwitchHUD: Bool?
        let lightState: String?
        let rule: SessionLighting.Rule?
    }

    private func state() -> [String: Any] {
        var slots: [[String: Any]] = rows.indices.map { index in
            if profile == .slack {
                let item = SlackDesktop.slots.indices.contains(index) ? SlackDesktop.slots[index] : nil
                return ["target":item?.conversation.deepLink.absoluteString ?? "", "title":item?.name ?? "",
                        "active":false, "state":item == nil ? SessionLight.empty.rawValue : "읽지 않음", "led":"0"]
            }
            if profile != .cmux {
                let row = sessions.indices.contains(index) ? sessions[index] : nil
                let light = row?.light ?? .empty
                return ["target":row?.url.absoluteString ?? "", "title":row?.title ?? "", "active":row != nil && row?.url == selectedSession, "state":light.rawValue, "led":light.agentCode]
            }
            let row = rows[index]
            return ["target": row?.id.uuidString ?? "", "title": row?.title ?? "",
                    "active": row?.active ?? false, "state": lights[index].rawValue, "led": lights[index].agentCode]
        }
        for i in slots.indices {
            if let state = slots[i]["state"] as? String, let style = (slotPalette ?? .initial).rules[state]?.slot {
                slots[i]["lightColor"] = style.effect == 0 ? "transparent" : style.color
            }
        }
        if profile == .t3 {
            for i in slots.indices where slots[i]["state"] as? String == SessionLight.empty.rawValue && sessions.indices.contains(i) && sessions[i] != nil {
                slots[i]["state"] = "비활성"
            }
        }
        let lightStatus = device?.lightingStatus ?? ""
        return ["profiles":profileList, "claudeOptions":claudeOptions(), "lightingStatus": lightStatus.isEmpty ? "USB 연결 대기" : lightStatus, "slots": slots, "usb": deviceStatus, "cmux": profile.hasRecentSessions ? sessionStatus : (profile == .cmux ? cmuxStatus : profile.title), "feedback": feedback,
                "profile": profile.rawValue, "automatic":automatic, "showAppSwitchHUD":appSwitchHUD.isEnabled,
                "globalMappings":Dictionary(uniqueKeysWithValues:KeyMap.controls.map { ($0,global[$0] ?? globalDefault($0)) }),
                "explicitGlobal":Array(global.keys).sorted(), "appOverrides":exportMaps,
                "explicitLocal":(profile == .cmux ? cmuxMappings : profiles[profile.rawValue] ?? [:]).filter { $0.value != "inherit" }.keys.sorted(),
                "localKeys":KeyMap.controls.filter { localValue($0,profile) != nil },
                "combinedSlots":combined.map { combinedRow($0) },
                "mappings": Dictionary(uniqueKeysWithValues: KeyMap.controls.map { ($0, binding($0, in:profile)) }),
                "defaults": Dictionary(uniqueKeysWithValues: KeyMap.controls.map { ($0, profile.defaultBinding($0)) }), "busy": selecting || connecting]
    }

    func respond(_ data: Data) async {
        guard let r = try? JSONDecoder().decode(Request.self, from: data) else {
            if let object = try? JSONSerialization.jsonObject(with:data) as? [String:Any], let id = object["id"] as? Int,
               var response = try? JSONSerialization.data(withJSONObject:["id":id,"error":"요청 형식을 확인하세요."]) {
                response.append(10)
                FileHandle.standardOutput.write(response)
            }
            return
        }
        var result: [String: Any] = ["id": r.id]
        do {
            switch r.method {
            case "controlPermission", "requestControlPermission":
                result["value"] = ControlPermission.status(requestPrompt:r.method == "requestControlPermission")
            case "state": result["value"] = state()
            case "readLighting","saveLighting":
                let current = palette ?? .initial
                if r.method == "saveLighting" {
                    guard let name = r.lightState, let rule = r.rule, current.rules[name] != nil else { throw CompanionError("알 수 없는 세션 상태입니다.") }
                    var rules = current.rules
                    rules[name] = rule
                    let next = SessionLighting(rules:rules)
                    guard next.valid else { throw CompanionError("조명 색상과 효과를 확인하세요.") }
                    KeyMap.preferences.set(try JSONEncoder().encode(next),forKey:"sessionLighting")
                    KeyMap.preferences.set(2,forKey:"slotPaletteVersion")
                    palette = next
                    device?.retryLighting()
                    updateLights()
                }
                result["value"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(palette ?? .initial))
            case "configureClaude":
                guard profile == .claudeCode, let control = r.input, let value = r.binding else { throw CompanionError("Claude Code 프로필을 선택하세요.") }
                switch control {
                case "source":
                    guard value.isEmpty || claudeCatalog.contains(where:{$0.source == value}) else { throw CompanionError("세션 소스가 변경되었습니다.") }
                    claudeSource = value
                    KeyMap.preferences.set(value,forKey:"claudeSessionSource")
                case "request":
                    let options = claudeOptions()["requests"] as? [[String:String]] ?? []
                    guard value.isEmpty || options.contains(where:{$0["id"] == value}) else { throw CompanionError("권한 요청이 종료되었습니다.") }
                    selectedRequest = value.isEmpty ? nil : value
                default:
                    guard (1...6).map(String.init).contains(control), value.isEmpty || sourceSessions.contains(where:{$0.item.url.absoluteString == value}) else { throw CompanionError("세션을 다시 선택하세요.") }
                    claudePins = claudePins.filter { $0.value != value }
                    claudePins[control] = value.isEmpty ? nil : value
                    KeyMap.preferences.set(claudePins,forKey:"claudeSlotPins")
                }
                rebuildClaudeSlots()
                result["value"] = state()
            case "exportMaps":

                var archive:[String:Any] = ["version":2,"profiles":exportMaps,"global":global]
                if enabled.contains(.claudeCode) { archive["claudeSlots"]=["source":claudeSource,"pins":claudePins] as [String:Any] }
                result["value"]=archive
            case "importMaps":
                guard let archive=r.archive else { throw CompanionError("키맵 파일 형식을 확인하세요.") }
                try archive.validate()
                if let values=archive.global { global=values; KeyMap.preferences.set(global,forKey:"globalBindings") }
                if let slots = archive.claudeSlots {
                    claudeSource = slots.source
                    claudePins = slots.pins
                    KeyMap.preferences.set(claudeSource,forKey:"claudeSessionSource")
                    KeyMap.preferences.set(claudePins,forKey:"claudeSlotPins")
                    if profile == .claudeCode { rebuildClaudeSlots() }
                }
                finishMic()
                for (id,overrides) in archive.profiles.sorted(by:{$0.key<$1.key}) {
                    guard let p=AppProfile(rawValue:id), p.selectable else { continue }
                    if !enabled.contains(p) {enabled.append(p)}
                    if id == "cmux" { cmuxMappings = overrides } else { profiles[id] = overrides }
                }
                storeEnabled()
                if profile == .unconfigured { activate(enabled.first ?? .unconfigured) }
                KeyMap.preferences.set(exportMaps,forKey:"keymapOverridesV1")
                updateLights()
                result["value"]=state()
            case "appMenus":
                guard let id=r.profile, let app=AppProfile(rawValue:id) else { throw CompanionError("대상 앱을 선택하세요.") }
                result["value"] = await Task.detached { ApplicationMenu.list(app) }.value
            case "runningApps": result["value"] = MacActions.runningApps()
            case "addFavorite":
                try MacActions.register(path:r.target,id:r.profile)
                result["value"] = MacActions.favorites
            case "removeFavorite":
                if let id=r.profile { MacActions.favorites[id] = nil }
                result["value"] = MacActions.favorites
            case "catalog":
                let orcaOverrides = try? OrcaControls.readOverrides()
                let orcaNeedsShortcut = OrcaCatalog.byBinding.compactMap { binding,action in
                    action.id != OrcaControls.codexTab && (try? OrcaControls.chord(for:action,overrides:orcaOverrides ?? [:])) == nil ? binding : nil
                }
                result["value"] = ["profiles": profileList, "templates":AppProfile.allCases.map { ["id":$0.rawValue,"name":$0.title] }, "controls": KeyMap.controls.map { ["id": $0, "name": KeyMap.name($0), "action": KeyMap.label($0)] },
                                   "presets":Dictionary(uniqueKeysWithValues:AppProfile.allCases.map { ($0.rawValue,KeyMap.preset($0)) }), "appDefaults":Dictionary(uniqueKeysWithValues:AppProfile.allCases.map { p in (p.rawValue,Dictionary(uniqueKeysWithValues:KeyMap.controls.map { ($0,p.defaultBinding($0)) })) }), "agentActions": Dictionary(uniqueKeysWithValues: AppProfile.allCases.map { ($0.rawValue,$0.agentActions) }), "orcaNeedsShortcut":orcaNeedsShortcut, "orcaGroups":OrcaCatalog.byBinding.mapValues(\.group), "targetActions":MacActions.targetLabels,"systemActions":MacActions.system, "favorites":MacActions.favorites, "slackActions": zip(SlackAction.inputs,SlackAction.labels).map { ["id":"slack."+$0.0,"name":$0.1] }, "modifiers": FunctionKey.modifiers, "special": FunctionKey.specialKeys] as [String: Any]
            case "addProfile":
                let next:AppProfile
                if let path=r.target, path.hasSuffix(".app"), let id=Bundle(url:URL(fileURLWithPath:path))?.bundleIdentifier {
                    guard let app=AppProfile(rawValue:"app."+id) else { throw CompanionError("앱 식별자를 확인하세요.") }
                    next = AppProfile.allCases.first(where:{$0.bundleIDs.contains(id)}) ?? app
                } else if let id=r.profile, let p=AppProfile(rawValue:id), AppProfile.allCases.contains(p) {next=p}
                else if let id=r.profile, MacActions.runningApps()[id] != nil, let app=AppProfile(rawValue:"app."+id) {
                    next=AppProfile.allCases.first(where:{$0.bundleIDs.contains(id)}) ?? app
                }
                else {throw CompanionError("앱을 선택하세요.")}
                if !enabled.contains(next) {enabled.append(next);storeEnabled()}
                var response=state();response["addedProfile"]=next.rawValue;result["value"]=response
            case "removeProfile":
                guard let id=r.profile, let p=AppProfile(rawValue:id), enabled.contains(p) else {throw CompanionError("키맵을 확인하세요.")}
                enabled.removeAll{$0==p}
                if p == .cmux { cmuxMappings=[:] } else { profiles[id]=nil }
                if p == .claudeCode {
                    claudePins = [:]
                    claudeSource = ""
                    KeyMap.preferences.removeObject(forKey:"claudeSlotPins")
                    KeyMap.preferences.removeObject(forKey:"claudeSessionSource")
                }
                storeEnabled()
                KeyMap.preferences.set(exportMaps,forKey:"keymapOverridesV1")
                if profile==p {activate(.unconfigured)}
                result["value"]=state()
            case "activateProfile":
                guard let id = r.profile, let next = AppProfile(rawValue:id), (enabled.contains(next) || next == .unconfigured) else { throw CompanionError("알 수 없는 키맵") }
                activate(next)
                result["value"] = state()
            case "setAppSwitchHUD":
                guard let enabled = r.showAppSwitchHUD else { throw CompanionError("HUD 설정값을 확인하세요.") }
                appSwitchHUD.isEnabled = enabled
                result["value"] = state()
            case "toggleAuto":
                toggleAutomatic()
                result["value"] = state()
            case "applyPreset":
                guard let id=r.profile, let p=AppProfile(rawValue:id), enabled.contains(p),
                      !KeyMap.preset(p).isEmpty else { throw CompanionError("프리셋을 사용할 앱을 선택하세요.") }
                var overrides = p == .cmux ? cmuxMappings : profiles[id] ?? [:]
                overrides.merge(KeyMap.preset(p)) { existing,_ in existing }
                if p == .cmux { cmuxMappings=overrides } else { profiles[id]=overrides }
                KeyMap.preferences.set(exportMaps,forKey:"keymapOverridesV1")
                if p == profile { updateLights() }
                result["value"]=state()
            case "save" where r.scope == "global":
                guard let key=r.input, KeyMap.controls.contains(key), let value=r.binding, KeymapArchive.common(value) else { throw CompanionError("글로벌 배정을 확인하세요.") }
                global[key]=value
                KeyMap.preferences.set(global,forKey:"globalBindings")
                updateLights()
                result["value"]=state()
            case "save":
                guard let id = r.profile, let p = AppProfile(rawValue:id), enabled.contains(p),
                      let input = r.input, KeyMap.controls.contains(input),
                      let binding = r.binding,
                      KeymapArchive.accepts(binding,input:input,profile:p) else {
                    throw CompanionError("단축키 조합을 확인하세요.")
                }
                save(binding, for: input, in:p)
                updateLights()
                result["value"] = state()
            case "select":
                guard r.profile == profile.rawValue else { throw CompanionError("키맵이 변경되었습니다.") }
                if let slot=combined.first(where:{ "combined:"+$0.id == r.target }) { try await openCombined(slot); break }
                if profile == .slack {
                    guard let slot = SlackDesktop.slots.first(where:{$0.conversation.deepLink.absoluteString == r.target}) else { throw CompanionError("Slack 대화 목록이 변경되었습니다.") }
                    try await SlackDesktop.open(slot.conversation)
                    break
                }
                if profile.hasRecentSessions {
                    guard let item = sessions.compactMap({$0}).first(where:{ $0.url.absoluteString == r.target }) else { throw CompanionError("세션이 변경되었습니다.") }
                    try await openSession(item,source:profile)
                    break
                }
                guard profile == .cmux else { throw CompanionError("빈 슬롯입니다.") }
                guard !selecting, !connecting, let target = r.target, let index = rows.firstIndex(where: { $0?.id.uuidString == target }) else {
                    throw CompanionError("슬롯이 변경되었습니다. 다시 선택하세요.")
                }
                select(index)
            case "suspendFirmware": stop(); connecting=false; deviceStatus="펌웨어 작업 중"
            case "resumeFirmware": start()
            case "connect": connect()
            case "readPrefs", "savePrefs":
                guard !preferencesBusy else { throw CompanionError("기기 설정을 처리 중입니다.") }
                preferencesBusy = true
                defer { preferencesBusy = false }
                let old = preferences
                let value = try await Task.detached {
                    if r.method == "readPrefs" { return try DevicePreferences.read() }
                    guard let old, old.value.revision == r.revision, let sleep = r.sleep, let volume = r.volume,
                          (0...120).contains(sleep), (0...100).contains(volume) else {
                        throw CompanionError("기기 설정을 다시 읽어 주세요.")
                    }
                    return try DevicePreferences.save(old, sleep: sleep, volume: volume, brightness: r.brightness, styles: r.styles)
                }.value
                preferences = value
                var settings: [String: Any] = ["sleep": value.value.sleepMinutes, "volume": value.value.volumePercent,
                                   "revision": value.value.revision, "buzzer": value.value.buzzerEnabled]
                settings["brightness"] = value.value.brightness
                settings["styles"] = value.value.styles
                result["value"] = settings
            default: throw CompanionError("알 수 없는 요청")
            }
        } catch { result["error"] = error.localizedDescription }
        if var bytes = try? JSONSerialization.data(withJSONObject: result) {
            bytes.append(10)
            FileHandle.standardOutput.write(bytes)
        }
    }
    func select(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        enqueue(.key(index + 1))
    }
}
