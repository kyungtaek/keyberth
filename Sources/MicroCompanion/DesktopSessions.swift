import AppKit
import MicroCore

struct DesktopSession {
    let url: URL
    let title: String
    var light: SessionLight
    var completionRevision: String? = nil
    var updated:Double = 0
}

enum DesktopSessions {
    static func visibleCodexSession(in items: [DesktopSession]) -> URL? {
        guard let window = try? ClaudeControls.window(.codex),
              let web = window.descendants({ $0.role == "AXWebArea" }, first:true).first,
              let location = web.url("AXURL") else { return nil }
        let route = (location.fragment ?? location.path).components(separatedBy:"?")[0]
        let parts = route.split(separator:"/")
        if parts.count >= 2, ["local","threads"].contains(String(parts[parts.count-2])),
           let id = UUID(uuidString:String(parts.last!)) {
            return items.first { UUID(uuidString:$0.url.lastPathComponent) == id }?.url
        }
        // Some desktop versions expose the shell URL and the chat title separately.
        let title = ClaudeControls.label(web)
        let matches = items.filter { !$0.title.isEmpty && $0.title == title }
        return matches.count == 1 ? matches[0].url : nil
    }
    static func read(_ profile: AppProfile, pendingT3Only: Bool = false) throws -> [DesktopSession] {
        if profile == .claude { return try ClaudeControls.sessions() }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codex = profile == .codex
        let db = home.appendingPathComponent(codex ? ".codex/state_5.sqlite" : ".t3/userdata/statev2.sqlite")
        let pending = "EXISTS (SELECT 1 FROM orchestration_v2_projection_runtime_requests q WHERE q.thread_id=t.thread_id AND q.status='pending')"
        let settled = "(coalesce(json_extract(t.payload_json,'$.settledOverride'),'')='settled' OR json_extract(t.payload_json,'$.settledAt') IS NOT NULL)"
        let scope = pendingT3Only ? "AND NOT "+settled+" AND "+pending : ""
        let limit = pendingT3Only ? "" : "LIMIT 6"
        let sql = codex ? """
            SELECT id, substr(coalesce(nullif(name,''), title),1,160) AS title, rollout_path, coalesce(recency_at_ms,updated_at_ms,updated_at*1000)/1000.0 AS updated
            FROM threads WHERE archived=0 AND originator IN ('Codex Desktop','codex_work_desktop')
            ORDER BY coalesce(recency_at_ms,updated_at_ms,updated_at*1000) DESC,id LIMIT 6
            """ : """
            SELECT thread_id AS id,substr(title,1,160) AS title, (julianday(updated_at)-2440587.5)*86400 AS updated,
            (SELECT CAST(r.ordinal AS TEXT) FROM orchestration_v2_projection_runs r WHERE r.thread_id=t.thread_id ORDER BY r.ordinal DESC LIMIT 1) AS revision,
            CASE WHEN \(settled) THEN 'settled'
            WHEN \(pending)
            THEN 'attention' ELSE (SELECT r.status FROM orchestration_v2_projection_runs r WHERE r.thread_id=t.thread_id ORDER BY r.ordinal DESC LIMIT 1) END AS status
            FROM orchestration_v2_projection_threads t WHERE archived_at IS NULL AND deleted_at IS NULL \(scope) ORDER BY updated_at DESC,thread_id \(limit)
            """
        func query(_ location: String) throws -> Data {
            try CmuxClient.run(["-readonly","-json",location,sql], executable:"/usr/bin/sqlite3")
        }
        let data: Data
        do { data = try query(db.path) }
        catch {
            // A closed WAL-mode database can lack shared memory. Only use the
            // checkpoint when there is no WAL containing newer transactions.
            guard !FileManager.default.fileExists(atPath:db.path+"-wal") else { throw error }
            data = try query(db.absoluteString+"?immutable=1")
        }
        guard !data.isEmpty else { return [] }
        struct Row: Decodable { let updated:Double?; let id: String; let title, rollout_path, status, revision: String? }
        let rows = try JSONDecoder().decode([Row].self, from:data)
        let turns = codex ? latestCodexTurns(rows.compactMap { UUID(uuidString:$0.id) }, home:home) : [:]
        var environment = "", version = ""
        if !codex {
            environment = try String(contentsOf:db.deletingLastPathComponent().appendingPathComponent("environment-id")).trimmingCharacters(in:.whitespacesAndNewlines)
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier:profile.bundleIDs[0]) {
                version = Bundle(url:app)?.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? ""
            }
        }
        return rows.compactMap { row in
            let url = codex ? (UUID(uuidString:row.id) == nil ? nil : URL(string:"codex://threads/"+row.id)) :
                T3Navigation.url(installedVersion:version,target:Key(environment:environment,thread:row.id))
            guard let url else { return nil }
            let states: [String:SessionLight] = ["attention":.attention,"running":.running,"completed":.done,"settled":.empty,"stopped":.empty,"interrupted":.ready,"cancelled":.empty]
            let (light,revision) = codex ? (turns[row.id.lowercased()] ?? rolloutState(row.rollout_path)) : (states[row.status ?? ""] ?? .unknown,row.revision)
            return DesktopSession(url:url,title:row.title ?? row.id,light:light,completionRevision:revision,updated:row.updated ?? 0)
        }
    }

    // T3's shortcut toggles settlement. Check the exact local thread first so
    // pressing the key on a settled chat cannot reopen it.
    static func t3NeedsSettlement(route:URL, home:URL = FileManager.default.homeDirectoryForCurrentUser) throws -> Bool {
        let directory = home.appendingPathComponent(".t3/userdata")
        let environment = try String(contentsOf:directory.appendingPathComponent("environment-id")).trimmingCharacters(in:.whitespacesAndNewlines)
        let path = route.fragment?.components(separatedBy:"?").first ?? route.path
        let parts = path.split(separator:"/")
        guard parts.count == 2, parts[0] == environment, let thread = UUID(uuidString:String(parts[1])) else {
            throw CompanionError("현재 로컬 T3 세션을 확인할 수 없습니다.")
        }
        let sql = """
            SELECT CASE WHEN json_extract(payload_json,'$.settledOverride')='settled'
                OR json_extract(payload_json,'$.settledAt') IS NOT NULL THEN 0 ELSE 1 END
            FROM orchestration_v2_projection_threads
            WHERE thread_id='\(thread.uuidString.lowercased())' AND archived_at IS NULL AND deleted_at IS NULL
            """
        let data = try CmuxClient.run(["-readonly",directory.appendingPathComponent("statev2.sqlite").path,sql],executable:"/usr/bin/sqlite3")
        switch String(decoding:data,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines) {
        case "0": return false
        case "1": return true
        default: throw CompanionError("정리할 T3 세션을 찾을 수 없습니다.")
        }
    }

    static func latestCodexTurns(_ ids:[UUID], home:URL) -> [String:(SessionLight,String?)] {
        guard !ids.isEmpty else { return [:] }
        let db = home.appendingPathComponent(".codex/thread_history_1.sqlite")
        let values = ids.map { "('" + $0.uuidString.lowercased() + "')" }.joined(separator:",")
        let sql = """
            WITH slots(id) AS (VALUES \(values))
            SELECT t.thread_id,t.turn_id,t.status FROM slots
            JOIN thread_turns t ON t.thread_id=slots.id AND t.turn_id=(
            SELECT turn_id FROM thread_turns WHERE thread_id=slots.id ORDER BY rollout_ordinal DESC LIMIT 1)
            """
        struct Turn: Decodable { let thread_id,turn_id,status:String }
        guard let data = try? CmuxClient.run(["-readonly","-json",db.path,sql],executable:"/usr/bin/sqlite3"),
              let turns = try? JSONDecoder().decode([Turn].self,from:data) else { return [:] }
        var result = [String:(SessionLight,String?)]()
        for turn in turns {
            switch turn.status {
            case "inProgress": result[turn.thread_id] = (.running,nil)
            case "completed": result[turn.thread_id] = (.done,turn.turn_id)
            case "interrupted","failed": result[turn.thread_id] = (.ready,nil)
            default: continue
            }
        }
        return result
    }

    static func rolloutState(_ path: String?) -> (SessionLight,String?) {
        guard let path, let file = FileHandle(forReadingAtPath:path) else { return (.unknown,nil) }
        defer { try? file.close() }
        guard let end = try? file.seekToEnd() else { return (.unknown,nil) }
        do {
            try file.seek(toOffset:end > 131072 ? end-131072 : 0)
            let data = try file.read(upToCount:131072) ?? Data()
            for line in data.split(separator:10).reversed() {
                guard let event = try? JSONSerialization.jsonObject(with:line) as? [String:Any],event["type"] as? String == "event_msg",
                      let payload = event["payload"] as? [String:Any] else { continue }
                switch payload["type"] as? String {
                case "task_complete","turn_complete": return (.done,payload["turn_id"] as? String)
                case "turn_aborted": return (.ready,nil)
                case "task_started","turn_started": return (.running,nil)
                default: continue
                }
            }
        } catch {}
        return (.unknown,nil)
    }

    @MainActor static func open(_ item: DesktopSession, profile: AppProfile) async throws {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier:(profile == .claudeCode ? AppProfile.claude : profile).bundleIDs[0]) else { throw CompanionError(profile.title+" 앱을 찾을 수 없습니다.") }
        if profile == .claude { try ClaudeControls.open(item.url); return }
        _ = try await NSWorkspace.shared.open([item.url], withApplicationAt:app, configuration:.init())
    }
}
