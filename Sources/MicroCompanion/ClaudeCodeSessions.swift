import Foundation
import MicroCore

enum ClaudeCodeSessions {
    struct Session { let item: DesktopSession; let cli: UUID; let updated: Double; let source:String }
    private struct Metadata: Decodable {
        let sessionId:String?
        let cliSessionId:String?
        let cwd:String?
        let title:String?
        private enum CodingKeys: String, CodingKey { case sessionId,cliSessionId,cwd,title,lastActivityAt,isArchived }
        let lastActivityAt:Double?
        init(from decoder:Decoder) throws {
            let values = try decoder.container(keyedBy:CodingKeys.self)
            sessionId = try values.decodeIfPresent(String.self, forKey:.sessionId)
            cliSessionId = try values.decodeIfPresent(String.self, forKey:.cliSessionId)
            title = try values.decodeIfPresent(String.self, forKey:.title)
            cwd = try values.decodeIfPresent(String.self, forKey:.cwd)
            isArchived = try values.decodeIfPresent(Bool.self, forKey:.isArchived)
            if let number = try? values.decode(Double.self, forKey:.lastActivityAt) {
                lastActivityAt = number < 10_000_000_000 ? number * 1000 : number
            } else if let text = try? values.decode(String.self, forKey:.lastActivityAt) {
                let format = ISO8601DateFormatter()
                format.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
                lastActivityAt = (format.date(from:text) ?? ISO8601DateFormatter().date(from:text)).map { $0.timeIntervalSince1970 * 1000 }
            } else { lastActivityAt = nil }
        }
        let isArchived:Bool?
    }
    static let folder=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Keyberth/ClaudeHooks")
    static func read() -> [Session] {
        let support=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        var rows=[String:Session]()
        for app in ["Claude","Claude-3p","Claude 3p"] {
            let root=support.appendingPathComponent(app+"/claude-code-sessions")
            guard let enumerator=FileManager.default.enumerator(at:root,includingPropertiesForKeys:[.contentModificationDateKey,.fileSizeKey],options:[.skipsHiddenFiles]) else { continue }
            for case let file as URL in enumerator {
                if enumerator.level > 4 { enumerator.skipDescendants(); continue }
                guard file.pathExtension=="json", file.lastPathComponent.hasPrefix("local_"),
                      let values=try? file.resourceValues(forKeys:[.contentModificationDateKey,.fileSizeKey]),
                      (values.fileSize ?? Int.max)<512*1024, let data=try? Data(contentsOf:file),
                      let meta=try? JSONDecoder().decode(Metadata.self,from:data),meta.isArchived != true,
                      let cli=meta.cliSessionId.flatMap(UUID.init(uuidString:)) else { continue }
                let id=meta.sessionId.flatMap { $0.hasPrefix("local_") ? $0 : nil } ?? file.deletingPathExtension().lastPathComponent
                guard id.hasPrefix("local_"),UUID(uuidString:String(id.dropFirst(6))) != nil,
                      let url=URL(string:"claude://claude.ai/epitaxy/"+id) else { continue }
                let updated=meta.lastActivityAt ?? (values.contentModificationDate?.timeIntervalSince1970 ?? 0)*1000
                let title=meta.title ?? meta.cwd.map { URL(fileURLWithPath:$0).lastPathComponent } ?? id
                let source = String(file.deletingLastPathComponent().path.dropFirst(support.path.count+1))
                if (rows[id]?.updated ?? -.infinity) < updated {
                    rows[id]=Session(item:DesktopSession(url:url,title:title,light:ClaudeCodeHook.light(cli), completionRevision:ClaudeCodeHook.revision(cli)),cli:cli,updated:updated,source:source)
                }
            }
        }
        return rows.values.sorted { $0.updated == $1.updated ? $0.cli.uuidString < $1.cli.uuidString : $0.updated > $1.updated }
    }
}

enum ClaudeCodeHook {
    private static let fs=FileManager.default
    private static var base:URL { ClaudeCodeSessions.folder }
    private static func stateURL(_ id:UUID) -> URL { base.appendingPathComponent(id.uuidString+".state") }
    static var lease:URL { base.appendingPathComponent("listener") }
    static func endLease() { try? fs.removeItem(at:lease) }
    static func heartbeat() {
        try? fs.createDirectory(at:base,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try? Data().write(to:lease,options:.atomic)
    }
    private static func fresh(_ url:URL,seconds:Double)->Bool {
        guard let date=try? url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate else {return false}
        return Date().timeIntervalSince(date)<seconds
    }
    static func requests(_ id:UUID)->[URL] {
        ((try? fs.contentsOfDirectory(at:base,includingPropertiesForKeys:nil)) ?? []).filter {
            $0.lastPathComponent.hasPrefix(id.uuidString+".") && $0.pathExtension=="request" && fresh($0,seconds:60)
        }
    }
    static func revision(_ id:UUID) -> String? {
        (try? stateURL(id).resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate).map { String($0.timeIntervalSince1970) }
    }
    static func light(_ id:UUID)->SessionLight {
        if !requests(id).isEmpty { return .attention }
        guard let raw=try? String(contentsOf:stateURL(id),encoding:.utf8),let state=SessionLight(rawValue:raw) else {return .unknown}
        return state
    }
    static func decide(_ allow:Bool,for url:URL?, requestID:String?) throws {
        guard let url, let session=ClaudeCodeSessions.read().first(where:{$0.item.url==url}) else {throw CompanionError("먼저 처리할 Claude Code 세션 키를 선택하세요.")}
        let pending=requests(session.cli).filter { requestID == nil || $0.lastPathComponent == requestID }
        guard pending.count==1 else {throw CompanionError("선택한 세션에 대기 중인 권한 요청이 정확히 한 건이어야 합니다.")}
        let answer=pending[0].appendingPathComponent("answer")
        try Data((allow ? "allow":"deny").utf8).write(to:answer,options:.withoutOverwriting)
    }

    // Claude passes JSON on stdin. Persist only event state and a random request
    // identifier. Tool arguments, messages and credentials never go into the keymap.
    static func run() throws {
        var input = Data()
        while input.count <= 1_048_576 {
            guard let part = try FileHandle.standardInput.read(upToCount:min(65_536,1_048_577-input.count)), !part.isEmpty else { break }
            input.append(part)
        }
        guard input.count<=1_048_576,let event=try JSONSerialization.jsonObject(with:input) as? [String:Any],
              let id=(event["session_id"] as? String).flatMap(UUID.init(uuidString:)),let name=event["hook_event_name"] as? String else {return}
        try fs.createDirectory(at:base,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let states:[String:SessionLight]=["SessionStart":.ready,"UserPromptSubmit":.running,"PreToolUse":.running,"PostToolUse":.running,"PostToolUseFailure":.attention,"Notification":.attention,"Stop":.done,"StopFailure":.attention,"SessionEnd":.empty]
        if name=="Notification", event["notification_type"] as? String == "idle_prompt" { try Data(SessionLight.ready.rawValue.utf8).write(to:stateURL(id),options:.atomic); return }
        if let state=states[name] {try Data(state.rawValue.utf8).write(to:stateURL(id),options:.atomic);return}
        guard name=="PermissionRequest",fresh(lease,seconds:8),ClaudeCodeSessions.read().contains(where:{$0.cli==id}) else {return}
        let request=base.appendingPathComponent(id.uuidString+"."+UUID().uuidString+".request")
        try fs.createDirectory(at:request,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        if let tool = event["tool_name"] as? String {
            try Data(tool.prefix(128).utf8).write(to:request.appendingPathComponent("tool"),options:.atomic)
        }
        defer {try? fs.removeItem(at:request)}
        let end=ProcessInfo.processInfo.systemUptime+55
        while ProcessInfo.processInfo.systemUptime<end, fresh(lease,seconds:8) {
            if let answer=try? String(contentsOf:request.appendingPathComponent("answer"),encoding:.utf8),["allow","deny"].contains(answer) {
                let response=["hookSpecificOutput":["hookEventName":"PermissionRequest","decision":["behavior":answer]]] as [String:Any]
                FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:response))
                return
            }
            Thread.sleep(forTimeInterval:0.15)
        }
    }
}
