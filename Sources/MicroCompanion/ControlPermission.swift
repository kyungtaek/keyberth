import ApplicationServices
import CoreGraphics

/// Check in the same process that reads other apps' UI and posts keyboard events.
enum ControlPermission {
    static func status(requestPrompt: Bool) -> [String: Bool] {
        let trusted: Bool
        if requestPrompt {
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            trusted = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
            if trusted && !CGPreflightPostEventAccess() { _ = CGRequestPostEventAccess() }
        } else {
            trusted = AXIsProcessTrusted()
        }
        return ["accessibility": trusted, "postEvents": CGPreflightPostEventAccess()]
    }
}
