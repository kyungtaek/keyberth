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
