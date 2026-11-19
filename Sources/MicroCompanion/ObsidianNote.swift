import AppKit

enum ObsidianNote {
    static let prefix = "obsidian-note:"
    static func path(_ binding:String) -> String? {
        guard binding.hasPrefix(prefix) else { return nil }
        let path=String(binding.dropFirst(prefix.count))
        guard path.hasPrefix("/"), URL(fileURLWithPath:path).pathExtension.lowercased()=="md" else { return nil }
        return path
    }
    static func open(_ path:String) throws {
        guard (try? URL(fileURLWithPath:path).resourceValues(forKeys:[.isRegularFileKey]).isRegularFile)==true else {
            throw CompanionError("지정한 문서를 찾을 수 없습니다. 문서를 다시 선택하세요.")
        }
        var parts=URLComponents()
        parts.scheme="obsidian"; parts.host="open"; parts.queryItems=[URLQueryItem(name:"path",value:path)]
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of:"+", with:"%2B")
        guard let url=parts.url, NSWorkspace.shared.open(url) else { throw CompanionError("Obsidian에서 문서를 열 수 없습니다.") }
    }
}
