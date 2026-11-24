import AppKit
import MicroCore

enum OrcaControls {
    static func chord(for action: OrcaCatalog.Action, overrides: [String:Any]) throws -> String {
        let raw = overrides[action.id]
        let candidates = raw.map { ($0 as? [String]) ?? ($0 as? String).map { [$0] } ?? [] } ?? action.defaults
        let aliases = ["mod":"cmd", "meta":"cmd", "super":"cmd", "option":"alt", "control":"ctrl",
                       "arrowleft":"left", "arrowright":"right", "arrowup":"up", "arrowdown":"down",
                       "bracketleft":"[", "bracketright":"]", "equal":"=", "minus":"-", "esc":"escape"]
        for candidate in candidates {
            var parts = candidate.lowercased().components(separatedBy:"+").map { aliases[$0] ?? $0 }
            guard var key = parts.popLast() else { continue }
            if let index = action.index {
                guard key == "1" || key == "digit1" else { continue }
                key = String(index)
            } else if key.hasPrefix("digit") && key.count == 5 {
                key = String(key.suffix(1))
            } else if key.hasPrefix("key") && key.count == 4 {
                key = String(key.suffix(1))
            } else if key == "plus" {
                key = "="
                if !parts.contains("shift") { parts.append("shift") }
            }
            let chord = (parts + [key]).joined(separator:"+")
            if DesktopShortcut.valid(chord) { return chord }
        }
        throw CompanionError("Orca 설정 → Shortcuts에서 ‘"+action.title+"’에 사용할 단축키를 지정하세요.")
    }

    static let codexTab = "tab.newAgent.codex"

    @MainActor static func launchCodex() async throws {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == AppProfile.orca.bundleIDs.first, let url = app.bundleURL else {
            throw CompanionError("Orca 창을 선택하세요.")
        }
        let cli = url.appendingPathComponent("Contents/Resources/bin/orca").path
        let result = try await Task.detached {
            try CmuxClient.run(["agent","launch","--agent","codex","--worktree","active","--focus","--json"],executable:cli,timeout:25)
        }.value
        struct Response: Decodable { let ok: Bool }
        guard try JSONDecoder().decode(Response.self,from:result).ok else {
            throw CompanionError("Orca에서 Codex를 열 수 없습니다.")
        }
    }

    static func readOverrides() throws -> [String:Any] {
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".orca/keybindings.json")
        var overrides = [String:Any]()
        if FileManager.default.fileExists(atPath:file.path) {
            guard let settings = try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any] else {
                throw CompanionError("Orca 단축키 설정 파일을 확인하세요.")
            }
            overrides = settings["keybindings"] as? [String:Any] ?? settings
            let platforms = settings["platforms"] as? [String:Any]
            overrides.merge(platforms?["darwin"] as? [String:Any] ?? [:]) { _,mac in mac }
        }
        return overrides
    }

    @MainActor static func press(_ action: OrcaCatalog.Action) throws -> () -> Void {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == AppProfile.orca.bundleIDs.first else {
            throw CompanionError("Orca 창을 선택하세요.")
        }
        return try DesktopShortcut.press(chord(for:action,overrides:readOverrides()),to:.orca)
    }
}
