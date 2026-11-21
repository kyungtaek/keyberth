# Slack 새 메시지로 키 LED 켜기

2026-11-21 공식 문서 조사. 실제 워크스페이스 수신과 Mac용 Slack 이동은 후속 검증 대상이다.

## 어떤 신호를 쓸까

DM 도착을 표시하려면 Slack 앱에 사용자 OAuth를 연결하고 사용자 이벤트를 구독한다. 봇 계정으로 받은 DM만 관찰하는 설정은 사용자가 동료와 주고받는 DM을 포함하지 않는다. 조직의 앱 설치 정책에 따라 관리자 승인이 필요할 수 있다. [Slack Events API](https://docs.slack.dev/apis/events-api/)

| 대화 | 이벤트 | 사용자 권한 |
| --- | --- | --- |
| 1:1 DM | message.im | im:history |
| 그룹 DM | message.mpim | mpim:history |
| 공개 채널 | message.channels | channels:history |
| 비공개 채널 | message.groups | groups:history |

신규 메시지에서 본인이 보낸 메시지와 수정·삭제 이벤트를 제외하고, 재전송은 event_id로 중복 제거한다. LED와 대화 열기에 필요한 워크스페이스·대화 ID와 메시지 시각만 보관하면 메시지 본문을 저장할 필요가 없다. [Slack 메시지 이벤트](https://docs.slack.dev/reference/events/message/)

## 첫 실측 시나리오

- 내부 워크스페이스에서 Socket Mode로 1:1 DM을 구독한다. 공개 HTTP 수신 서버 없이 WebSocket으로 수신할 수 있다. 공용 배포판에는 공용 앱 토큰을 넣지 않는다. Slack Marketplace 공개 등록을 추진하면 HTTPS 수신 방식을 사용한다. [Socket Mode](https://docs.slack.dev/apis/events-api/using-socket-mode/)
- 다른 사용자가 보낸 DM으로 LED를 켠다. 키를 누르면 Slack 딥링크로 해당 워크스페이스의 상대방 DM을 연다. [Slack 딥링크](https://docs.slack.dev/interactivity/deep-linking/)
- 휴대폰에서 먼저 읽는 경우까지 확인한다. DM 읽기 권한으로 conversations.info의 DM 읽음 상태를 확인한 후 LED를 끈다. 채널에서는 같은 방식의 미확인 건수를 전제하지 않는다. [대화 정보와 읽음 필드](https://docs.slack.dev/reference/methods/conversations.info/)

## macOS 배너와의 차이

메시지가 도착해도 음소거, 알림 일정, 채널별 알림 설정에 따라 배너는 표시되지 않을 수 있다. macOS의 UNUserNotificationCenter는 호출한 앱에 전달된 알림을 조회하므로 Keyberth가 Slack의 배너를 구독하는 용도로 쓸 수 없다. 제품 설정에서는 표시 기준을 ‘새 DM’이나 ‘선택한 채널의 새 메시지’로 명시한다. [Slack 알림 설정](https://slack.com/help/articles/360025446073-Guide-to-Slack-notifications) · [Apple 알림 조회 API](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getdeliverednotifications%28completionhandler%3A%29)
