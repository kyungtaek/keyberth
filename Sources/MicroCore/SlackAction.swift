import Foundation

public enum SlackAction {
    public static let labels = (1...6).map { "최근 안 읽은 대화 \($0)" } + [
        "이전 글", "다음 글", "답글 스레드 열기", "스레드 닫기", "Slackbot 새 질문", "새 메시지 작성", "보내기",
        "이전 페이지", "다음 페이지", "이전 새 글 채널", "다음 새 글 채널"]
    public static let inputs = (1...13).map { String(format:"K%02d", $0) } + ["JOY_LEFT","JOY_RIGHT","JOY_UP","JOY_DOWN"]
    public static func binding(_ input: String) -> String? {
        inputs.contains(input) ? "slack." + input : nil
    }
    public static func input(_ binding: String) -> String? {
        guard binding.hasPrefix("slack.") else { return nil }
        let id = String(binding.dropFirst(6))
        return inputs.contains(id) ? id : nil
    }
}

extension SlackAction {
    public static func permalink(_ url:URL) -> (channel:String,timestamp:String)? {
        let parts=url.pathComponents
        guard let host=url.host?.lowercased(), host=="slack.com" || host.hasSuffix(".slack.com"),
              parts.count==4, parts[1]=="archives",
              parts[2].range(of:"^[CDG][A-Z0-9]+$",options:.regularExpression) != nil,
              parts[3].range(of:"^p[0-9]{16}$",options:.regularExpression) != nil else { return nil }
        return (parts[2],String(parts[3].dropFirst()))
    }
}

/// A slot belongs to a workspace and a conversation. Names can be duplicated
/// across workspaces and message links can carry thread query parameters.
public struct SlackConversation: Equatable, Hashable {
    public let team, channel:String
    public init?(team:String,channel:String) {
        guard team.range(of:"^T[A-Z0-9]+$",options:.regularExpression) != nil,
              channel.range(of:"^[CDG][A-Z0-9]+$",options:.regularExpression) != nil else { return nil }
        self.team=team;self.channel=channel
    }
    public var deepLink:URL { URL(string:"slack://channel?team="+team+"&id="+channel)! }
    public static func workspace(_ url:URL) -> String? {
        guard url.scheme == "https", url.host == "app.slack.com", url.pathComponents.count >= 3,
              url.pathComponents[1] == "client" else { return nil }
        let id=url.pathComponents[2]
        return id.range(of:"^T[A-Z0-9]+$",options:.regularExpression) == nil ? nil : id
    }
    public static func parse(_ url:URL, currentTeam:String?) -> Self? {
        if let team=workspace(url), url.pathComponents.count >= 4 { return Self(team:team,channel:url.pathComponents[3]) }
        if url.scheme == "slack",url.host == "channel",let items=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems,
           let team=items.first(where:{$0.name=="team"})?.value,let id=items.first(where:{$0.name=="id"})?.value { return Self(team:team,channel:id) }
        guard url.scheme=="https",let host=url.host,host.hasSuffix(".slack.com") || host=="slack.com",
              let team=currentTeam,url.pathComponents.count>=3,url.pathComponents[1]=="archives" else { return nil }
        return Self(team:team,channel:url.pathComponents[2])
    }
}
