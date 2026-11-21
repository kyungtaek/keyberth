import AppKit
import MicroCore

/// Resolve by full menu path again on press. Menu items and enabled states can change between windows.
enum ApplicationMenu {
    static func path(_ binding:String) -> [String]? {
        guard binding.hasPrefix("menu:"), binding.utf8.count <= 4096,
              let parts = try? JSONDecoder().decode([String].self,from:Data(binding.dropFirst(5).utf8)),
              (2...12).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && !$0.contains("\0") }) else { return nil }
        return parts
    }
    private static func bar(_ profile:AppProfile) -> AppNode? {
        guard [.codex,.cmux,.t3].contains(profile), let id = profile.bundleIDs.first,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier:id).first else { return nil }
        return AppNode(element:AXUIElementCreateApplication(app.processIdentifier)).node("AXMenuBar")
    }
    static func list(_ profile:AppProfile) -> [String:String] {
        guard let bar = bar(profile) else { return [:] }
        var actions = [String:String]()
        func visit(_ item:AppNode, _ parents:[String]) {
            guard parents.count < 12, let title = item.attr("AXTitle") as? String, !title.isEmpty else { return }
            let parts = parents + [title]
            if let menu = item.children.first(where:{ $0.role == "AXMenu" }) {
                for child in menu.children where child.role == "AXMenuItem" { visit(child,parts) }
            } else if parts.count >= 2, let data = try? JSONEncoder().encode(parts) {
                actions["menu:"+String(decoding:data,as:UTF8.self)] = parts.joined(separator:" › ")
            }
        }
        for top in bar.children where top.role == "AXMenuBarItem" { visit(top,[]) }
        return actions
    }
    static func perform(_ parts:[String], profile:AppProfile) throws {
        guard let bar = bar(profile) else { throw CompanionError(profile.title+" 메뉴를 확인할 수 없습니다.") }
        var items = bar.children
        for (index,title) in parts.enumerated() {
            let matches = items.filter { $0.attr("AXTitle") as? String == title }
            guard matches.count == 1, matches[0].attr("AXEnabled") as? Bool != false else { break }
            if index == parts.count-1 { try matches[0].press(); return }
            items = matches[0].children.first(where:{ $0.role == "AXMenu" })?.children ?? []
        }
        throw CompanionError("현재 창에서 이 메뉴를 사용할 수 없습니다 · "+parts.joined(separator:" › "))
    }
}
