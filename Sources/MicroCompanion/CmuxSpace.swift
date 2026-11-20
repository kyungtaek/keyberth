import Foundation
import MicroCore

/// A terminal exposes a held Space as repeated bytes. Capture the surface at
/// press time and never queue repeats behind an outstanding cmux request.
@MainActor final class CmuxSpace {
    private var pressed: String?
    private var generation = UUID()
    private var task: Task<Void, Never>?
    func press(_ key: String, onError: @escaping (String) -> Void) {
        guard pressed == nil else { return }
        let previous = task
        let token = UUID()
        pressed = key
        generation = token
        task = Task {
            await previous?.value
            do {
                struct Location: Decodable {
                    let window_id, workspace_id, surface_id: UUID
                    let surface_type: String
                }
                struct Identity: Decodable { let focused: Location?; let socket_path: String }
                let (target,socketPath) = try await Task.detached {
                    let response = try CmuxClient.run(["--json","--id-format","uuids","identify"])
                    let identity = try JSONDecoder().decode(Identity.self, from:response)
                    guard let location = identity.focused,
                          ["terminal","agent-session"].contains(location.surface_type) else {
                        throw CompanionError("활성 cmux 터미널이 없습니다.")
                    }
                    return (location,identity.socket_path)
                }.value
                guard !Task.isCancelled else { return }
                let params = ["window_id":target.window_id.uuidString, "workspace_id":target.workspace_id.uuidString,
                              "surface_id":target.surface_id.uuidString, "text":" "]
                let connection = try await Task.detached { try CmuxRepeatConnection(path:socketPath) }.value
                guard !Task.isCancelled else { return }
                func space() async throws {
                    try await Task.detached { try connection.space(params) }.value
                }
                try await space()
                guard pressed == key, generation == token else { return }
                try await Task.sleep(for:.milliseconds(300))
                while pressed == key, generation == token, !Task.isCancelled {
                    try await space()
                    try await Task.sleep(for:.milliseconds(30))
                }
            } catch is CancellationError {} catch { onError(error.localizedDescription) }
        }
    }
    func release(_ key:String) {
        if pressed == key { pressed = nil }
    }
    func cancel() {
        pressed = nil
        generation = UUID()
        task?.cancel()
    }
}
