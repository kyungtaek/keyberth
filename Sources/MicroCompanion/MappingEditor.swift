import SwiftUI
import MicroCore

enum KeyMap {
    static let preference = "physicalKeyMappings"
    static let keys = (1...13).map { String(format: "K%02d", $0) }
    static let knob = ["ENC_CCW", "ENC_CW"]
    static let stick = ["JOY_UP", "JOY_DOWN", "JOY_LEFT", "JOY_RIGHT"]
    static let controls = keys + knob + stick
    static let actions = (1...6).map { "최근 세션 \($0)" } + Deck.labels
        + ["이전 세션", "다음 세션", "위 패널로 이동", "아래 패널로 이동", "왼쪽 패널로 이동", "오른쪽 패널로 이동"]
    static func code(_ input: DeckInput) -> String {
        switch input {
        case .key(let n): return String(format: "K%02d", n)
        case .turn(let delta): return delta < 0 ? knob[0] : knob[1]
        case .direction(let d): return "JOY_" + d.uppercased()
        }
    }
    static func name(_ code: String) -> String {
        if let i = keys.firstIndex(of: code) { return "키 \(i+1)" }
        if let i = knob.firstIndex(of: code) { return ["노브 반시계 방향", "노브 시계 방향"][i] }
        if let i = stick.firstIndex(of: code) { return ["방향키 위", "방향키 아래", "방향키 왼쪽", "방향키 오른쪽"][i] }
        return code
    }
    static func label(_ binding: String) -> String {
        controls.firstIndex(of: binding).map { actions[$0] } ?? binding
    }
    static func load() -> [String:String] {
        let defaults = UserDefaults.standard
        if let saved = defaults.dictionary(forKey: preference) as? [String:String] { return saved }
        let legacy = defaults.dictionary(forKey: "functionShortcuts") as? [String:String] ?? [:]
        var result: [String:String] = [:]
        for (k, v) in legacy {
            if let n = Int(k), FunctionKey.range.contains(n), let chord = FunctionKey.shortcut(v) { result[keys[n]] = chord }
        }
        return result
    }
}

struct MappingEditor: View {
    @ObservedObject var model: Companion
    @State private var selected = "K07"
    @State private var drafts: [String: Draft] = [:]
    @State private var message = ""
    @State private var hover: String?
    private static let custom = "custom"
    private let accent = DeckBrand.accent
    private struct Draft: Equatable {
        var choice: String
        var chord: String
    }
    private static let artwork: NSImage? = {
        let url = Bundle.main.url(forResource: "keypad", withExtension: "png") ?? Bundle.module.url(forResource: "keypad", withExtension: "png")
        return url.flatMap(NSImage.init(contentsOf:))
    }()
    // Key centres in the square illustration, in a 400-point coordinate space.
    private let centres: [CGPoint] = [(168,94),(235,94),(101,163),(168,163),(235,163),(302,163),
                                      (101,231),(168,231),(235,231),(302,231),(168,300),(235,300),(302,300)]
        .map { CGPoint(x: $0.0, y: $0.1) }
    private var current: String { model.mappings[selected] ?? selected }
    private var saved: Draft {
        if KeyMap.controls.contains(current) { return Draft(choice: current, chord: "") }
        return Draft(choice: Self.custom, chord: current)
    }
    private var editing: Draft { drafts[selected] ?? saved }
    private var value: String? {
        editing.choice == Self.custom ? FunctionKey.shortcut(editing.chord) : editing.choice
    }
    private var directions: [String] {
        if KeyMap.knob.contains(selected) { return KeyMap.knob }
        return KeyMap.stick.contains(selected) ? KeyMap.stick : []
    }
    private func update(_ new: Draft) {
        drafts[selected] = new == saved ? nil : new
        message = ""
    }
    private func save() {
        guard let value else { return }
        model.save(value, for: selected)
        drafts.removeValue(forKey: selected)
        message = "저장됨"
    }
    private func directionLabel(_ id: String) -> String {
        switch id {
        case "ENC_CCW": return "반시계"
        case "ENC_CW": return "시계"
        case "JOY_UP": return "↑"
        case "JOY_DOWN": return "↓"
        case "JOY_LEFT": return "←"
        default: return "→"
        }
    }
    private var inspector: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("편집할 컨트롤").font(.caption).foregroundStyle(.secondary)
            Picker("편집할 컨트롤", selection: $selected) {
                ForEach(KeyMap.controls, id: \.self) { Text(KeyMap.name($0)).tag($0) }
            }.labelsHidden().accessibilityLabel("편집할 컨트롤")
            if !directions.isEmpty {
                Picker("입력 방향", selection: $selected) {
                    ForEach(directions, id: \.self) { id in
                        Text(directionLabel(id)).accessibilityLabel(KeyMap.name(id)).tag(id)
                    }
                }.labelsHidden().pickerStyle(.segmented).accessibilityLabel("입력 방향")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("현재 동작").font(.caption).foregroundStyle(.secondary)
                Text(KeyMap.label(current)).font(.system(size: 21, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.vertical, 4)
            Divider()
            Text("배정할 동작").font(.headline)
            Picker("배정할 동작", selection: Binding(get: { editing.choice }, set: {
                update(Draft(choice: $0, chord: editing.chord))
            })) {
                Section("세션 선택") { actionOptions(Array(KeyMap.keys.prefix(6)) + KeyMap.knob) }
                Section("패널 이동") { actionOptions(KeyMap.stick) }
                Section("작업") { actionOptions(Array(KeyMap.keys.dropFirst(6))) }
                Divider()
                Text("터미널 단축키…").tag(Self.custom)
            }.labelsHidden().accessibilityLabel("배정할 동작")
            if editing.choice == Self.custom {
                TextField("예: ctrl+a", text: Binding(get: { editing.chord }, set: {
                    update(Draft(choice: Self.custom, chord: $0))
                })).textFieldStyle(.roundedBorder).accessibilityLabel("터미널 단축키").onSubmit { save() }
                if value == nil {
                    Text("ctrl+a, alt+left, enter처럼 입력하세요.").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("저장", action: save).buttonStyle(.borderedProminent)
                    .disabled(value == nil || drafts[selected] == nil).keyboardShortcut("s", modifiers: .command)
                Button("취소") { drafts.removeValue(forKey: selected); message = "" }.disabled(drafts[selected] == nil)
            }
            if drafts[selected] != nil || !message.isEmpty {
                Text(drafts[selected] == nil ? message : "저장 전 변경사항").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("기본 동작으로 되돌리기") { update(Draft(choice: selected, chord: "")) }
                .controlSize(.small).disabled(editing.choice == selected)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
    }
    private func actionOptions(_ ids: [String]) -> some View {
        ForEach(ids, id: \.self) { Text(KeyMap.label($0)).tag($0) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(DeckBrand.name).font(.system(size: 24, weight: .bold, design: .rounded))
                Divider().frame(height: 20)
                Text("키 매핑").font(.title3)
                Spacer()
                Text("cmux").font(.system(.body, design: .monospaced))
            }.padding(.horizontal, 24).frame(height: 64)
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    deviceMap.clipShape(RoundedRectangle(cornerRadius: 12))
                    HStack {
                        Text("AI Micro").font(.system(.body, design: .rounded).weight(.semibold))
                        Spacer()
                        Text("변경할 키를 선택하세요").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(18)
                Divider()
                inspector.frame(width: 266)
            }
            Divider()
            HStack {
                Image(systemName: "cable.connector")
                Text(model.deviceStatus)
                Spacer()
                Text(model.cmuxStatus)
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 22).frame(height: 34)
        }.fixedSize().background(Color(nsColor: .windowBackgroundColor)).tint(accent)
            .onChange(of: selected) { _ in message = "" }
    }
    private var deviceMap: some View {
        let scale: CGFloat = 1.04
        return ZStack(alignment: .topLeading) {
            if let artwork = Self.artwork {
                Image(nsImage: artwork).resizable().scaledToFit().frame(width:400*scale,height:400*scale)
                    .accessibilityHidden(true)
            }
            ForEach(Array(KeyMap.keys.enumerated()), id: \.offset) { i,id in
                marker(id, title:String(i+1), point:centres[i], scale:scale)
            }
            marker(KeyMap.knob.contains(selected) ? selected : "ENC_CCW", title:"↶↷", point:CGPoint(x:101,y:88),scale:scale)
            marker(KeyMap.stick.contains(selected) ? selected : "JOY_UP", title:"✥", point:CGPoint(x:302,y:95),scale:scale)
        }.frame(width:400*scale,height:400*scale,alignment:.topLeading).clipped()
    }
    private func marker(_ id:String, title:String, point:CGPoint, scale:CGFloat) -> some View {
        Button { selected = id } label: {
            Text(title).font(.system(size:14,weight:.bold,design:.rounded))
                .foregroundStyle(selected == id ? Color.white : Color.black)
                .padding(.horizontal,6).frame(minWidth:25,minHeight:25)
                .background(selected == id ? accent : Color.white.opacity(0.90),in:Capsule())
                .overlay(Capsule().strokeBorder(hover == id ? accent : .clear,lineWidth:2))
                .frame(width:47,height:44).contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { inside in hover = inside ? id : nil }
            .help(KeyMap.name(id) + " · " + KeyMap.label(model.mappings[id] ?? id))
            .accessibilityLabel(KeyMap.name(id)).accessibilityValue(KeyMap.label(model.mappings[id] ?? id))
            .accessibilityAddTraits(selected == id ? .isSelected : [])
            .position(x:point.x*scale,y:point.y*scale)
    }
}
