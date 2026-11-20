import Foundation
import AppKit
import MicroCore

enum CmuxClient {
    static func run(_ args: [String], executable: String = "/Applications/cmux.app/Contents/Resources/bin/cmux") throws -> Data {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let deadline = ProcessInfo.processInfo.systemUptime + 4
        let fd = output.fileHandleForReading.fileDescriptor
        var data = Data(), bytes = [UInt8](repeating: 0, count: 8192)
        while ProcessInfo.processInfo.systemUptime < deadline && data.count <= 8_000_000 {
            var item = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&item, 1, 100) > 0 else { continue }
            let n = read(fd, &bytes, bytes.count)
            if n <= 0 {
                if process.isRunning { usleep(10000); continue }
                guard process.terminationStatus == 0 else {
                    throw CompanionError(String(decoding: data.prefix(400), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
                }
                return data
            }
            data.append(contentsOf: bytes.prefix(n))
        }
        if process.isRunning { process.terminate() }
        throw CompanionError("cmux 응답 시간 또는 크기 제한 초과")
    }
    static func list() throws -> [CmuxTarget] {
        try CmuxTarget.targets(run(["--json", "--id-format", "uuids", "tree", "--all"]))
    }
    static func signal(_ target: CmuxTarget) throws -> WorkspaceSignal {
        let data = try run(["--json", "--id-format", "uuids", "workspace", "status",
                            "--workspace", target.workspace.uuidString, "--window", target.window.uuidString])
        let signal = try JSONDecoder().decode(WorkspaceSignal.self, from: data)
        guard signal.workspace_id == target.workspace else { throw CompanionError("작업공간 상태 불일치") }
        return signal
    }
    static func send(_ chord: String, to target: CmuxTarget) async throws {
        guard let key = FunctionKey.shortcut(chord),
              try list().contains(where: { $0.active && $0.sameLocation(as: target) }) else {
            throw CompanionError("활성 터미널이 변경되어 단축키 전송을 취소했습니다.")
        }
        if key.split(separator:"+").dropLast().contains("cmd") {
            try await DesktopShortcut.send(key, to:.cmux)
            return
        }
        // cmux accepts the named "space" key but emits no byte for it.
        _ = try run([key == "space" ? "send" : "send-key", "--window", target.window.uuidString, "--workspace",
                     target.workspace.uuidString, "--surface", target.id.uuidString, key == "space" ? " " : key])
    }
    static func focus(_ target: CmuxTarget) throws {
        guard try list().contains(where: { $0.sameLocation(as: target) }) else { throw CompanionError("세션이 종료되거나 이동했습니다.") }
        let window = ["--window", target.window.uuidString]
        let workspace = ["--workspace", target.workspace.uuidString] + window
        _ = try run(["select-workspace"] + workspace)
        _ = try run(["focus-panel", "--panel", target.id.uuidString] + workspace)
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.cmuxterm.app" {
            _ = try run(["-a", "/Applications/cmux.app"], executable: "/usr/bin/open")
        }
        _ = try run(["focus-window"] + window)
    }
}

extension CmuxClient {
    static func perform(_ input: DeckInput, override: String?) async throws {
        let live = try list()
        guard let index = live.firstIndex(where: \.active) else { throw CompanionError("활성 cmux 터미널이 없습니다.") }
        let target = live[index]
        let workspace = ["--workspace", target.workspace.uuidString, "--window", target.window.uuidString]
        let surface = ["--surface", target.id.uuidString] + workspace
        if let override { try await send(override, to: target); return }
        switch input {
        case .turn(let step):
            try focus(live[(index + live.count + step) % live.count])
        case .direction(let direction):
            try focusNeighbor(direction, target, workspace)
        case .key(7): _ = try run(["new-workspace", "--window", target.window.uuidString, "--focus", "true"])
        case .key(8), .key(9): try reply(to: target, approve: input == .key(8), surface: surface)
        case .key(10): _ = try run(["right-sidebar", "show"] + workspace)
        case .key(11): try await send("space", to: target)
        case .key(12):
            let record = try CodexBinding.recordForFork(target, surface: surface)
            guard let record, let checkpoint = record["checkpoint_id"] as? String, !checkpoint.isEmpty else {
                throw CompanionError("이 터미널에 포크할 대화 기록이 없습니다.")
            }
            let bin = "/Applications/cmux.app/Contents/Resources/bin/"
            let fork: String
            if record["kind"] as? String == "codex", let parent = UUID(uuidString: checkpoint) {
                let id = parent.uuidString.lowercased()
                fork = "env CMUX_AGENT_FORK_PARENT_SESSION_ID=" + id + " " + bin + "cmux-codex-wrapper fork " + id
            } else if (record["fork_command"] as? String)?.isEmpty == false ||
                        (record["fork_arguments"] as? [String])?.isEmpty == false {
                fork = bin + "cmux fork --surface " + target.id.uuidString
            } else {
                throw CompanionError("이 대화에는 실행 가능한 포크 명령이 없습니다.")
            }
            _ = try run(["new-split", "right", "--focus", "true", "--command", fork] + surface)
        case .key(13): try await send("enter", to: target)
        default: break
        }
    }

    private static func focusNeighbor(_ direction: String, _ target: CmuxTarget, _ workspace: [String]) throws {
        struct Pane: Decodable {
            struct Frame: Decodable { let x, y, width, height: Double }
            let id: UUID
            let selected_surface_id: UUID?
            let pixel_frame: Frame
        }
        struct Layout: Decodable { let panes: [Pane] }
        let panes = try JSONDecoder().decode(Layout.self, from: run(["--json","--id-format","uuids","list-panes"] + workspace)).panes
        guard let current = panes.first(where: { $0.selected_surface_id == target.id }) else { return }
        let a = current.pixel_frame
        let horizontal = ["left","right"].contains(direction)
        let positive = ["right","down"].contains(direction)
        func axes(_ f: Pane.Frame) -> (Double,Double,Double,Double) {
            horizontal ? (f.x,f.x+f.width,f.y,f.y+f.height) : (f.y,f.y+f.height,f.x,f.x+f.width)
        }
        let (start,end,low,high) = axes(a)
        let options = panes.compactMap { p -> (UUID,Double,Double)? in
            let (s,e,l,h) = axes(p.pixel_frame)
            let gap = positive ? s-end : start-e
            guard p.id != current.id, gap >= -1, min(high,h) > max(low,l) else { return nil }
            return (p.id, gap, abs(low+high-l-h))
        }
        if let id = options.min(by: { ($0.1,$0.2) < ($1.1,$1.2) })?.0 {
            _ = try run(["focus-pane","--pane",id.uuidString] + workspace)
        }
    }

    static func resume(_ surface: [String]) throws -> [String:Any]? {
        let data = try run(["--json","surface","resume","get"] + surface)
        let root = try JSONSerialization.jsonObject(with: data) as? [String:Any]
        return root?["restore_record"] as? [String:Any] ?? root?["resume_binding"] as? [String:Any]
    }
    private static func reply(to target: CmuxTarget, approve: Bool, surface: [String]) throws {
        let record = try resume(surface)
        let checkpoint = (record?["checkpoint_id"] ?? record?["checkpoint"]) as? String
        let data = try run(["--json","rpc","feed.list"])
        let feed = try JSONSerialization.jsonObject(with: data) as? [String:Any]
        let matches = (feed?["items"] as? [[String:Any]] ?? []).filter { item in
            guard item["kind"] as? String == "permissionRequest", item["status"] as? String == "pending" else { return false }
            if let id = item["surface_id"] as? String { return UUID(uuidString: id) == target.id }
            guard let checkpoint, !checkpoint.isEmpty, let workstream = item["workstream_id"] as? String else { return false }
            if workstream == checkpoint { return true }
            let fields = workstream.components(separatedBy: ":")
            guard fields.count == 3, fields[0] == "cmux-feed-v1", let session = Data(base64Encoded: fields[2]) else { return false }
            return String(data: session, encoding: .utf8) == checkpoint
        }
        guard matches.count == 1, let id = matches[0]["request_id"] as? String else {
            throw CompanionError("현재 대화의 승인 요청 한 건을 식별할 수 없습니다. cmux Feed를 확인하세요.")
        }
        let params = try JSONSerialization.data(withJSONObject: ["request_id":id,"mode":approve ? "once" : "deny"])
        guard try list().contains(where: { $0.active && $0.sameLocation(as: target) }) else { throw CompanionError("활성 세션이 바뀌었습니다.") }
        let response = try run(["--json","rpc","feed.permission.reply",String(decoding: params, as: UTF8.self)])
        guard (try JSONSerialization.jsonObject(with: response) as? [String:Bool])?["delivered"] == true else {
            throw CompanionError("승인 요청이 이미 종료됐습니다.")
        }
    }
}
