import Foundation

public struct SessionLighting: Codable, Equatable {
    public struct Style: Codable, Equatable {
        public let color: String
        public let effect: Int
        public init(color: String, effect: Int) { self.color = color; self.effect = effect }
        var valid: Bool {
            color.count == 7 && color.first == "#" && color.dropFirst().allSatisfy { $0.isASCII && $0.isHexDigit } && (0...6).contains(effect)
        }
        var fields: [String: Any] {
            ["c": Int(color.dropFirst(), radix:16) ?? 0, "e":effect, "b":0.55, "s":0.5]
        }
    }
    public struct Rule: Codable, Equatable {
        public let slot, ambient: Style
        public init(slot: Style, ambient: Style) { self.slot = slot; self.ambient = ambient }
    }
    public let rules: [String:Rule]
    public init(rules: [String:Rule]) { self.rules = rules }
    public var valid: Bool {
        Set(rules.keys) == Set(SessionLight.allCases.map(\.rawValue)) && rules.values.allSatisfy { $0.slot.valid && $0.ambient.valid }
    }
    public static let initial = Self(rules:Dictionary(uniqueKeysWithValues: SessionLight.allCases.map { state in
        let color: String
        switch state {
        case .attention: color="#FF9800"
        case .running: color="#268AFF"
        case .unknown: color="#939DA5"
        default: color=String(format:"#%06X",state.rgb)
        }
        let effect = [.unknown,.empty].contains(state) ? 0 : ([.attention,.running].contains(state) ? 4 : 1)
        return (state.rawValue,Rule(slot:Style(color:color,effect:effect),ambient:Style(color:color,effect:state == .running ? 2 : (state == .attention ? 4 : 0))))
    }))

    /// Migrate only unchanged factory colors, preserving user-selected colors,
    /// animation effects and the separate ambient configuration.
    public var migratingLegacySlotColors: Self {
        let previous: [SessionLight:String] = [.active:"#13965B",.ready:"#52677A",.done:"#9863DA",.attention:"#EF5350"]
        var updated=rules
        for (state,color) in previous {
            guard let rule=rules[state.rawValue], rule.slot.color == color,
                  let replacement=Self.initial.rules[state.rawValue]?.slot.color else { continue }
            updated[state.rawValue]=Rule(slot:Style(color:replacement,effect:rule.slot.effect),ambient:rule.ambient)
        }
        return Self(rules:updated)
    }

    public func breathingSlot(states:[SessionLight], viewed:Int?) -> Int? {
        guard rules[SessionLight.running.rawValue]?.slot == Self.initial.rules[SessionLight.running.rawValue]?.slot else { return nil }
        if let viewed, states.indices.contains(viewed), states[viewed] == .running { return viewed }
        return states.firstIndex(of:.running)
    }

    private func ambientState(states:[SessionLight],selected:Int?) -> SessionLight {
        let priority: [SessionLight] = [.attention,.running,.done,.active,.ready,.unknown,.empty]
        let focus = selected.flatMap { states.indices.contains($0) && states[$0] != .empty ? states[$0] : nil }
        return focus ?? priority.first(where:states.contains) ?? .empty
    }

    public func agentStyles(states:[SessionLight], selected:Int?, includeAmbient:Bool) -> [String] {
        guard valid, states.count == 6 else { return [] }
        func payload(_ target:Int, _ style:Style) -> String {
            "\(target):\(style.color.dropFirst()):\(style.effect):55:50"
        }
        var styles = states.enumerated().map { payload($0.offset+1, rules[$0.element.rawValue]!.slot) }
        if includeAmbient {
            styles.append(payload(0,rules[ambientState(states:states,selected:selected).rawValue]!.ambient))
        }
        return styles
    }

    public func commands(states:[SessionLight], selected:Int?, firstID:Int, firmwareSlot:Int? = nil) throws -> [[[UInt8]]] {
        guard valid, states.count == 6 else { throw LED.Invalid.colors }
        let ambient = ambientState(states:states,selected:selected)
        let slots = states.enumerated().compactMap { index, state -> [String:Any]? in
            guard index != firmwareSlot else { return nil }
            var item = rules[state.rawValue]!.slot.fields
            item["id"] = index
            return item
        }
        return try [basicFrames(["id":firstID,"method":"v.oai.thstatus","params":slots]),
                    basicFrames(["id":firstID+1,"method":"v.oai.rgbcfg","params":["ambient":rules[ambient.rawValue]!.ambient.fields]])]
    }
}
