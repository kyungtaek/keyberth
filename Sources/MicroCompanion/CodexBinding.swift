import Foundation
import MicroCore

/// A fork's argv names its parent. Only the writable rollout belongs to the live conversation.
enum CodexBinding {
    private struct Owner: Equatable {
        let pid: Int
        let executable: String
    }
    private struct Conversation: Equatable {
        let id: UUID
        let cwd: String
    }
    private static let lock = NSLock()

    private static func owners() throws -> [String: [Owner]] {
        let ps = try CmuxClient.run(["-axo", "pid=,tty=,pgid=,tpgid=,comm="], executable: "/bin/ps")
        var result = [String: [Owner]]()
        for line in String(decoding: ps, as: UTF8.self).split(separator: "\n") {
            let cols = line.split(maxSplits: 4, whereSeparator: \.isWhitespace)
            guard cols.count == 5, cols[1].hasPrefix("ttys"), cols[2] == cols[3],
                  let pid = Int(cols[0]) else { continue }
            let path = String(cols[4]).trimmingCharacters(in: .whitespaces)
            guard path.hasPrefix("/"), URL(fileURLWithPath: path).lastPathComponent == "codex" else { continue }
            result[String(cols[1]), default: []].append(Owner(pid: pid, executable: path))
        }
        return result
    }
    private static func conversation(_ owner: Owner, tty: String) throws -> Conversation? {
        let files = try CmuxClient.run(["-nP","-a","-p",String(owner.pid),"-Ffan"], executable: "/usr/sbin/lsof")
        var fd = "", access = "", cwd: String?, terminal = false
        var ids = Set<UUID>()
        for line in String(decoding: files, as: UTF8.self).split(separator: "\n") {
            let value = String(line.dropFirst())
            switch line.first {
            case "f": fd = value; access = ""
            case "a": access = value
            case "n":
                if fd == "cwd" { cwd = value }
                if fd == "0", value == "/dev/" + tty { terminal = true }
                guard ["u","w"].contains(access) else { continue }
                let name = URL(fileURLWithPath: value).lastPathComponent
                guard name.hasPrefix("rollout-"), name.hasSuffix(".jsonl"),
                      let id = UUID(uuidString: String(name.dropLast(6).suffix(36))) else { continue }
                ids.insert(id)
            default: break
            }
        }
        guard terminal, ids.count == 1, let id = ids.first, let cwd else { return nil }
        return Conversation(id: id, cwd: cwd)
    }
    private static func flags(_ target: CmuxTarget) -> [String] {
        ["--workspace",target.workspace.uuidString,"--window",target.window.uuidString,"--surface",target.id.uuidString]
    }

    private static func reconcile(_ target: CmuxTarget, owner: Owner, tty: String) throws -> [String:Any] {
        let surface = flags(target)
        guard let live = try conversation(owner, tty: tty) else { throw CompanionError("Codex 대화가 열리는 중입니다.") }
        let record = try CmuxClient.resume(surface)
        if record?["kind"] as? String == "codex",
           (record?["checkpoint_id"] as? String).flatMap(UUID.init(uuidString:)) == live.id {
            return record ?? [:]
        }
        guard try CmuxClient.list().contains(where: { $0.sameLocation(as: target) && $0.tty == tty }),
              try owners()[tty] == [owner], try conversation(owner, tty: tty) == live else {
            throw CompanionError("Codex 패널이 변경됐습니다.")
        }
        let id = live.id.uuidString.lowercased()
        _ = try CmuxClient.run(["surface","resume","set"] + surface + ["--kind","codex","--checkpoint",id,
                       "--cwd",live.cwd,"--",owner.executable,"resume",id])
        guard let saved = try CmuxClient.resume(surface),
              (saved["checkpoint_id"] as? String).flatMap(UUID.init(uuidString:)) == live.id else {
            throw CompanionError("cmux 복원 ID 확인 실패")
        }
        return saved
    }

    static func refresh(_ live: [CmuxTarget]) {
        guard lock.try() else { return }
        defer { lock.unlock() }
        guard let processes = try? owners() else { return }
        for target in live {
            guard let tty = target.tty, let matches = processes[tty], matches.count == 1 else { continue }
            _ = try? reconcile(target, owner: matches[0], tty: tty)
        }
    }
    static func recordForFork(_ target: CmuxTarget, surface: [String]) throws -> [String:Any]? {
        lock.lock()
        defer { lock.unlock() }
        if let tty = target.tty, let matches = try owners()[tty] {
            guard matches.count == 1 else { throw CompanionError("현재 패널의 Codex 프로세스를 특정할 수 없습니다.") }
            return try reconcile(target, owner: matches[0], tty: tty)
        }
        return try CmuxClient.resume(surface)
    }
}
