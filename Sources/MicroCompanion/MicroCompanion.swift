import AppKit
import MicroCore

@main struct MicroCompanion {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--claude-hook") { try? ClaudeCodeHook.run(); return }
        if CommandLine.arguments.contains("--check-device") {
            do {
                let (path, location, _) = try AgentDevice.port()
                try AgentDevice.verify(path)
                print("USB CDC: " + AgentDevice.firmware)
                var reply: String?
                let hid = try AgentHID(location: location, status: { reply = $0 }, press: { _ in })
                let deadline = Date().addingTimeInterval(8)
                while reply == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
                hid.close()
                guard let reply, reply.hasPrefix("USB 연결됨") else { throw CompanionError(reply ?? "USB HID 응답 시간 초과") }
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
    private var automatic = KeyMap.preferences.bool(forKey: "automaticKeyMap")
    private var focusObserver: NSObjectProtocol?
    var feedback = ""

    private func hud(_ subtitle: String) {
        let event = ["event":"hud", "title":profile.title, "subtitle":subtitle]
        if var bytes = try? JSONSerialization.data(withJSONObject:event) {
            bytes.append(10)
            FileHandle.standardOutput.write(bytes)
        }
    }
    private func activate(_ next: AppProfile, notify: Bool = true) {
        guard next != profile else { return }
        finishMic()
        selectedClaudeCode = nil
        if profile == .claudeCode { ClaudeCodeHook.endLease() }
        if next == .claude || next == .claudeCode { KeyMap.preferences.set(next.rawValue, forKey:"preferredClaudeProfile") }
        if profile == .slack { slackQueue.removeAll(); slackTask?.cancel(); SlackDesktop.clearSlots() }
        profile = next
        sessionStatus = next.title
        sessionGeneration = UUID()
        sessions = []
        updateLights()
        refreshDesktop()
        KeyMap.preferences.set(next.rawValue, forKey:"selectedKeyMap")
        if notify { hud("현재 키맵") }
    }
    private func follow(_ bundle: String?, notify: Bool = true) {
        guard automatic, let bundle, let next = AppProfile.allCases.first(where: { $0.bundleIDs.contains(bundle) }) else { return }
        activate(next == .claude && KeyMap.preferences.string(forKey:"preferredClaudeProfile") == AppProfile.claudeCode.rawValue ? .claudeCode : next, notify:notify)
    }
    private func toggleAutomatic() {
        automatic.toggle()
        KeyMap.preferences.set(automatic, forKey:"automaticKeyMap")
        follow(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, notify:false)
        hud(automatic ? "자동 전환 켬" : "자동 전환 끔")
    }
    private func binding(_ input: String, in p: AppProfile) -> String {
        if p == .cmux { return cmuxMappings[input] ?? input }
        return profiles[p.rawValue]?[input] ?? p.defaultBinding(input)
    }
    private func save(_ value: String, for input: String, in p: AppProfile) {
        if p == .cmux {
            cmuxMappings[input] = value == input ? nil : value

        } else {
            profiles[p.rawValue, default: [:]][input] = value == p.defaultBinding(input) ? nil : value

        }
        KeyMap.preferences.set(exportMaps,forKey:"keymapOverridesV1")
    }
    private var exportMaps: [String:[String:String]] {
        Dictionary(uniqueKeysWithValues:AppProfile.allCases.map { ($0.rawValue,$0 == .cmux ? cmuxMappings : profiles[$0.rawValue] ?? [:]) })
    }
    private let cmuxSpace = CmuxSpace()
    private var micProfile: AppProfile?
    private var micKeys = Set<String>()
    private func finishMic() {
        cmuxSpace.cancel()
        guard let held = micProfile else { return }
        micProfile = nil
        micKeys.removeAll()
        do {
            try ClaudeControls.press(["stop dictation","finish dictation","starting dictation; click to cancel","받아쓰기 종료","받아쓰기 중지","받아쓰기 중단"],in:held)
        } catch { feedback = error.localizedDescription; hud(feedback) }
    }
    private func release(_ physical: DeckInput) {
        cmuxSpace.release(KeyMap.code(physical))
        guard micKeys.remove(KeyMap.code(physical)) != nil, micKeys.isEmpty else { return }
        finishMic()
    }
    private var selectedClaudeCode: URL? { didSet { if selectedClaudeCode != oldValue { selectedRequest = nil } } }
    private var completions = CompletionIndicator()
    private func indicator(_ item:DesktopSession) -> DesktopSession {
        var result = item
        result.light = completions.display(item.light, id:item.url.absoluteString, revision:item.completionRevision)
        return result
    }
    private var selectedRequest: String?
    private var claudeCatalog = [ClaudeCodeSessions.Session]()
    private var claudeSource = KeyMap.preferences.string(forKey:"claudeSessionSource") ?? ""
    private var claudePins = KeyMap.preferences.dictionary(forKey:"claudeSlotPins") as? [String:String] ?? [:]
    private var sourceSessions: [ClaudeCodeSessions.Session] { claudeCatalog.filter { claudeSource.isEmpty || $0.source == claudeSource } }
    private func rebuildClaudeSlots() {
        let items = sourceSessions
        var remaining = items.filter { !claudePins.values.contains($0.item.url.absoluteString) }.makeIterator()
        sessions = (1...6).map { slot in
            if let pin=claudePins[String(slot)] { return items.first(where:{$0.item.url.absoluteString == pin})?.item }
            return remaining.next()?.item
        }
        sessions = sessions.map { $0.map(indicator) }
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
                sessions = items.map(indicator)
                sessionStatus = source.title + " · 슬롯 " + String(items.count) + "/6"
            } catch {
                guard generation == sessionGeneration else { return }
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
    private func updateLights() {
        if profile == .cmux { device?.display(lights, selected: rows.firstIndex { $0?.active == true }, palette:palette); return }
        let states: [SessionLight] = KeyMap.keys.prefix(6).map { key in
            guard let index = recentIndex(binding(key,in:profile)), sessions.indices.contains(index) else { return .empty }
            return sessions[index]?.light ?? .empty
        }
        device?.display(states,selected:profile == .claudeCode ? sessions.firstIndex(where:{$0 != nil && $0?.url == selectedClaudeCode}) : nil,palette:palette)
    }
    private func recentIndex(_ value:String) -> Int? { (1...6).first { value == "recent."+String($0) }.map { $0-1 } }
    private var queue: [(DeckInput, CmuxTarget?, String?)] = []
    private func handle(_ physical: DeckInput) {
        let code = KeyMap.code(physical)
        switch physical {
        case .turn(let direction): activate(profile.advanced(by:direction)); return
        case .knobPress: toggleAutomatic(); return
        default: break
        }
        let binding = binding(code, in:profile)
        if profile == .cmux, binding == "K11" || binding == "space" {
            cmuxSpace.press(code) { [weak self] in self?.feedback = $0 }
            return
        }
        if profile == .codex || profile == .claude || profile == .claudeCode {
            let target:AppProfile = profile == .codex ? .codex : .claude
            // Session keys may bring Claude forward. Plain shortcuts only go to
            // the intended foreground application, as in the vendor binding table.
            if !binding.hasPrefix("recent."), !target.bundleIDs.contains(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "") { return }
        }
        if profile != .cmux {
            guard binding != "none" else { return }
            if profile == .slack, let input = SlackAction.input(binding) {
                slackQueue.append(input)
                runSlackActions()
                return
            }
            do {
                if let index = recentIndex(binding), profile.hasRecentSessions {
                    guard sessions.indices.contains(index), let item = sessions[index] else { throw CompanionError("빈 세션 슬롯입니다.") }
                    let source = profile
                    Task {
                        do { try await openSession(item,source:source) }
                        catch { feedback = error.localizedDescription; hud(feedback) }
                    }
                } else if binding.hasPrefix("agent."), profile.agentActions[binding] != nil {
                    if profile == .claudeCode { try ClaudeCodeHook.decide(binding == "agent.approve",for:selectedClaudeCode,requestID:selectedRequest) }
                    else if profile == .t3 { performT3(binding) }
                    else if binding == "agent.mic" {
                        if micProfile == nil { try AssistantControls.perform(binding,in:profile); micProfile=profile }
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
                    if let target { remember(target.id) }
                    feedback = ""
                } catch { feedback = error.localizedDescription }
            }
            selecting = false
            refresh()
        }
    }
    private var history = (KeyMap.preferences.stringArray(forKey: "recentSurfaces") ?? []).compactMap(UUID.init(uuidString:))
    private func remember(_ id: UUID) {
        guard history.first != id else { return }
        history.removeAll { $0 == id }
        history.insert(id, at: 0)
        history = Array(history.prefix(6))
        KeyMap.preferences.set(history.map(\.uuidString), forKey: "recentSurfaces")
    }
    var selecting = false
    var connecting = false
    private var device: AgentHID?
    private var epoch = UUID()
    private var refreshing = false
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        focusObserver = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification, object:nil, queue:.main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.follow(app?.bundleIdentifier) }
        }
        follow(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, notify:false)
        connect()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func stop() {
        if profile == .claudeCode { ClaudeCodeHook.endLease() }
        finishMic()
        if let focusObserver { NSWorkspace.shared.notificationCenter.removeObserver(focusObserver); self.focusObserver = nil }
        timer?.invalidate()
        timer = nil
        epoch = UUID()
        device?.close()
        device = nil
    }
    func connect() {
        guard !connecting, !selecting else { return }
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
                let location = try await Task.detached {
                    let (path, location, _) = try AgentDevice.port()
                    try AgentDevice.verify(path)
                    return location
                }.value
                guard epoch == token else { return }
                deviceStatus = "Universal Agent 세션 연결 중"
                device = try AgentHID(location: location, status: { [weak self] message in
                    if self?.epoch == token { self?.deviceStatus = message; if message.contains("다시 연결") { self?.finishMic() } }
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
        if profile == .claudeCode, deviceStatus.hasPrefix("USB 연결됨") { ClaudeCodeHook.heartbeat() }
        refreshDesktop()
        guard profile == .cmux else { return }
        guard !refreshing, !selecting, !connecting else { return }
        let token = epoch
        refreshing = true
        Task {
            defer { refreshing = false }
            do {
                let live = try await Task.detached { try CmuxClient.list() }.value
                guard epoch == token, !selecting else { return }
                if let active = live.first(where: \.active) { remember(active.id) }
                let recent = Deck.recent(live: live, history: history)
                rows = (0..<6).map { $0 < recent.count ? recent[$0] : nil }
                let current = rows
                let states = await Task.detached {
                    CodexBinding.refresh(live)
                    var signals: [UUID: WorkspaceSignal] = [:]
                    for group in Dictionary(grouping: current.compactMap { $0 }, by: \.workspace).values {
                        if let target = group.first { signals[target.workspace] = try? CmuxClient.signal(target) }
                    }
                    return current.map { row -> SessionLight in
                        guard let row else { return .empty }
                        return signals[row.workspace]?.light(active: row.active) ?? .unknown
                    }
                }.value
                guard epoch == token else { return }
                let cmuxFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == AppProfile.cmux.bundleIDs.first
                lights = zip(current,states).map { row,state in
                    guard let row else { return .empty }
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
        let input, binding, target, profile: String?
        let volume, sleep: Int?
        let archive: KeymapArchive?
        let revision: UInt32?
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
                return ["target":row?.url.absoluteString ?? "", "title":row?.title ?? "", "active":profile == .claudeCode && row != nil && row?.url == selectedClaudeCode, "state":light.rawValue, "led":light.agentCode]
            }
            let row = rows[index]
            return ["target": row?.id.uuidString ?? "", "title": row?.title ?? "",
                    "active": row?.active ?? false, "state": lights[index].rawValue, "led": lights[index].agentCode]
        }
        for i in slots.indices {
            if let state = slots[i]["state"] as? String, let style = (palette ?? .initial).rules[state]?.slot {
                slots[i]["lightColor"] = style.effect == 0 ? "transparent" : style.color
            }
        }
        let lightStatus = device?.lightingStatus ?? ""
        return ["claudeOptions":claudeOptions(), "lightingStatus": lightStatus.isEmpty ? "USB 연결 대기" : lightStatus, "slots": slots, "usb": deviceStatus, "cmux": profile.hasRecentSessions ? sessionStatus : (profile == .cmux ? cmuxStatus : profile.title), "feedback": feedback,
                "profile": profile.rawValue, "automatic":automatic,
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
                result["value"] = ["version":1,"profiles":exportMaps,"claudeSlots":["source":claudeSource,"pins":claudePins] as [String:Any]] as [String:Any]
            case "importMaps":
                guard let archive=r.archive else { throw CompanionError("키맵 파일 형식을 확인하세요.") }
                try archive.validate()
                if let slots = archive.claudeSlots {
                    claudeSource = slots.source
                    claudePins = slots.pins
                    KeyMap.preferences.set(claudeSource,forKey:"claudeSessionSource")
                    KeyMap.preferences.set(claudePins,forKey:"claudeSlotPins")
                    if profile == .claudeCode { rebuildClaudeSlots() }
                }
                finishMic()
                for (id,overrides) in archive.profiles {
                    if id == "cmux" { cmuxMappings = overrides } else { profiles[id] = overrides }
                }
                KeyMap.preferences.set(exportMaps,forKey:"keymapOverridesV1")
                updateLights()
                result["value"]=state()
            case "catalog":
                result["value"] = ["profiles": AppProfile.allCases.map { ["id":$0.rawValue,"name":$0.title] }, "controls": KeyMap.controls.map { ["id": $0, "name": KeyMap.name($0), "action": KeyMap.label($0)] },
                                   "agentActions": Dictionary(uniqueKeysWithValues: AppProfile.allCases.map { ($0.rawValue,$0.agentActions) }), "slackActions": zip(SlackAction.inputs,SlackAction.labels).map { ["id":"slack."+$0.0,"name":$0.1] }, "modifiers": FunctionKey.modifiers, "special": FunctionKey.specialKeys] as [String: Any]
            case "activateProfile":
                guard let id = r.profile, let next = AppProfile(rawValue:id) else { throw CompanionError("알 수 없는 키맵") }
                activate(next)
                result["value"] = state()
            case "toggleAuto":
                toggleAutomatic()
                result["value"] = state()
            case "save":
                guard let id = r.profile, let p = AppProfile(rawValue:id),
                      let input = r.input, KeyMap.controls.contains(input), AppProfile.fixedAction(input) == nil,
                      let binding = r.binding,
                      KeymapArchive.accepts(binding,input:input,profile:p) else {
                    throw CompanionError("단축키 조합을 확인하세요.")
                }
                save(binding, for: input, in:p)
                updateLights()
                result["value"] = state()
            case "select":
                guard r.profile == profile.rawValue else { throw CompanionError("키맵이 변경되었습니다.") }
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
                    return try DevicePreferences.save(old, sleep: sleep, volume: volume)
                }.value
                preferences = value
                result["value"] = ["sleep": value.value.sleepMinutes, "volume": value.value.volumePercent,
                                   "revision": value.value.revision, "buzzer": value.value.buzzerEnabled] as [String: Any]
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
