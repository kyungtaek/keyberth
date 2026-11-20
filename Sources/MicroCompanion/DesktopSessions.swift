import AppKit
import MicroCore

struct DesktopSession {
    let url: URL
    let title: String
    var light: SessionLight
    var completionRevision: String? = nil
}

enum DesktopSessions {
    static func read(_ profile: AppProfile, pendingT3Only: Bool = false) throws -> [DesktopSession] {
        if profile == .claude { return try ClaudeControls.sessions() }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codex = profile == .codex
        let db = home.appendingPathComponent(codex ? ".codex/state_5.sqlite" : ".t3/userdata/statev2.sqlite")
        let pending = "EXISTS (SELECT 1 FROM orchestration_v2_projection_runtime_requests q WHERE q.thread_id=t.thread_id AND q.status='pending')"
        let scope = pendingT3Only ? "AND "+pending : ""
        let limit = pendingT3Only ? "" : "LIMIT 6"
        let sql = codex ? """
            SELECT id, substr(coalesce(nullif(name,''), title),1,160) AS title, rollout_path
            FROM threads WHERE archived=0 AND originator IN ('Codex Desktop','codex_work_desktop')
            ORDER BY coalesce(recency_at_ms,updated_at_ms,updated_at*1000) DESC,id LIMIT 6
            """ : """
            SELECT thread_id AS id,substr(title,1,160) AS title,
            (SELECT CAST(r.ordinal AS TEXT) FROM orchestration_v2_projection_runs r WHERE r.thread_id=t.thread_id ORDER BY r.ordinal DESC LIMIT 1) AS revision,
            CASE WHEN \(pending)
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
        struct Row: Decodable { let id: String; let title, rollout_path, status, revision: String? }
        let rows = try JSONDecoder().decode([Row].self, from:data)
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
            let states: [String:SessionLight] = ["attention":.attention,"running":.running,"completed":.done,"interrupted":.ready]
            let (light,revision) = codex ? rolloutState(row.rollout_path) : (states[row.status ?? ""] ?? .unknown,row.revision)
            return DesktopSession(url:url,title:row.title ?? row.id,light:light,completionRevision:revision)
        }
    }

    private static func rolloutState(_ path: String?) -> (SessionLight,String?) {
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
                case "task_complete","turn_complete": return (.done,event["timestamp"] as? String)
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
