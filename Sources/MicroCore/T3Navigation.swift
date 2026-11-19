import Foundation

/// Pure stock T3 v0.1.7 native route construction. Does not open URLs or access live sessions.
public enum T3Navigation {
    public static func url(installedVersion: String, target: Key) -> URL? {
        guard installedVersion == "0.1.7", valid(target.environment), valid(target.thread) else { return nil }
        var components = URLComponents()
        components.scheme = "t3code"
        components.host = "threads"
        components.path = "/\(target.environment)/\(target.thread)"
        return components.url
    }

    private static func valid(_ value: String) -> Bool {
        guard (1...128).contains(value.utf8.count), value != ".", value != ".." else { return false }
        return value.utf8.allSatisfy {
            switch $0 {
            case 45, 46, 48...57, 65...90, 95, 97...122, 126: return true
            default: return false
            }
        }
    }
}
