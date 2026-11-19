import SwiftUI
import MicroCore

@main struct MicroCompanion: App {
    @NSApplicationDelegateAdaptor(Companion.self) private var model
    init() {
        if CommandLine.arguments.contains("--check-device") {
            do {
                let (path, location) = try AgentDevice.port()
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
    }
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor final class Companion: NSObject, ObservableObject, NSApplicationDelegate {
    private var statusMenu: StatusMenu?
    private var slotWindow: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusMenu = StatusMenu(model: self)
        start()
        if CommandLine.arguments.contains("--show-slots") { showSlots() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusMenu?.open()
        return true
    }
    private func showSlots() {
        if slotWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SlotPanel(model: self)))
            window.title = DeckBrand.name + " · cmux"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            statusMenu?.linkButton(to: window)
            slotWindow = window
        }
        slotWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationWillTerminate(_ notification: Notification) { stop() }
    @Published var deviceStatus = "USB 확인 대기"
    @Published var cmuxStatus = "cmux 확인 대기"
    @Published var rows = [CmuxTarget?](repeating: nil, count: 6)
    @Published var lights = Array(repeating: SessionLight.empty, count: 6)
    private var mappingWindow: NSWindow?
    func showMapping() {
        statusMenu?.close()
        if mappingWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: MappingEditor(model: self)))
            window.title = DeckBrand.name + " · 키 매핑"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            mappingWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        mappingWindow?.makeKeyAndOrderFront(nil)
    }
    @Published private(set) var mappings = KeyMap.load()
    @Published var feedback = ""
    func save(_ binding: String, for input: String) {
        if binding == input { mappings.removeValue(forKey: input) }
        else { mappings[input] = binding }
        UserDefaults.standard.set(mappings, forKey: KeyMap.preference)
    }
    private var queue: [(DeckInput, CmuxTarget?, String?)] = []
    private func handle(_ physical: DeckInput) {
        let code = KeyMap.code(physical)
        let binding = mappings[code] ?? code
        if let action = DeckInput(id: binding) { enqueue(action) }
        else if let chord = FunctionKey.shortcut(binding) { enqueue(physical, chord: chord) }
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
                        else { try CmuxClient.perform(input, override: override) }
                    }.value
                    if let target { remember(target.id) }
                    feedback = ""
                } catch { feedback = error.localizedDescription }
            }
            selecting = false
            refresh()
        }
    }
    private var history = (UserDefaults.standard.stringArray(forKey: "recentSurfaces") ?? []).compactMap(UUID.init(uuidString:))
    private func remember(_ id: UUID) {
        guard history.first != id else { return }
        history.removeAll { $0 == id }
        history.insert(id, at: 0)
        history = Array(history.prefix(6))
        UserDefaults.standard.set(history.map(\.uuidString), forKey: "recentSurfaces")
    }
    @Published var selecting = false
    @Published var connecting = false
    private var device: AgentHID?
    private var epoch = UUID()
    private var refreshing = false
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        connect()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func stop() {
        timer?.invalidate()
        timer = nil
        epoch = UUID()
        device?.close()
        device = nil
    }
    func connect() {
        guard !connecting, !selecting else { return }
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
                    let (path, location) = try AgentDevice.port()
                    try AgentDevice.verify(path)
                    return location
                }.value
                guard epoch == token else { return }
                deviceStatus = "Universal Agent 세션 연결 중"
                device = try AgentHID(location: location, status: { [weak self] message in
                    if self?.epoch == token { self?.deviceStatus = message }
                }, press: { [weak self] key in
                    guard self?.epoch == token else { return }
                    self?.handle(key)
                })
            } catch { deviceStatus = error.localizedDescription }
            connecting = false
            refresh()
        }
    }
    func refresh() {
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
                lights = states
                cmuxStatus = "cmux 연결됨 · 슬롯 \(rows.compactMap { $0 }.count)/6"
            } catch {
                guard epoch == token else { return }
                rows = Array(repeating: nil, count: 6)
                lights = Array(repeating: .empty, count: 6)
                cmuxStatus = "cmux 연결 실패 · \(error.localizedDescription)"
            }
            device?.display(lights, selected: rows.firstIndex { $0?.active == true })
        }
    }
    func select(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        enqueue(.key(index + 1))
    }
}
