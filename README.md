# Keyberth

Electron 기반 macOS 앱입니다. 키 매핑·최근 세션·기기 설정은 HTML/CSS로 표시하며, Swift 브리지가 USB HID·시리얼 통신과 cmux 명령 실행을 맡습니다. 개발 실행은 Node.js 22.12 이상과 Swift 환경에서 `npm ci && npm start`를 사용합니다. 기존 Mac 사용자 설정의 키 배정과 최근 세션을 그대로 읽습니다.

macOS 메뉴 막대에서 USB로 연결한 Universal Agent 0.2.18의 여섯 세션 키를 cmux 터미널에 연결합니다. cmux가 내부 프로세스의 소켓 접근만 허용하는 환경에서는 **cmux 터미널 안에서** 아래 실행 파일을 시작합니다. 터미널을 열어 두세요.

```sh
bash scripts/package.sh
./dist/MicroCompanion.app/Contents/MacOS/MicroCompanion
```

실행 명령 끝에 `--show-slots`를 붙이면 같은 여섯 버튼을 일반 창에서도 사용할 수 있습니다.

메뉴 막대 키보드 아이콘에서 연결 상태와 슬롯을 확인할 수 있습니다. 1–6번은 최근 활성화된 터미널 순서이며 1번이 가장 최근입니다. 관찰한 세션이 여섯 개 미만이면 현재 열린 터미널로 채웁니다. 종료한 세션은 목록에서 빠집니다. 다른 앱을 사용하는 중에 세션 키를 누르면 cmux가 전면으로 오면서 해당 터미널을 선택합니다. USB 재연결은 메뉴의 **다시 연결**을 사용합니다.

앱은 USB 시리얼에서 제조사의 `UPDATE_INFO`로 기종과 버전을 확인하고, 같은 USB 위치의 Universal Agent HID(usage page FF31, usage 1, report 7)에서 세션을 엽니다. AMHELLO로 펌웨어와 기능을 확인하고 AMMODE와 AMKEYMODE를 설정합니다. AMINPUT이 키 입력을 전달하고, AMFRAME과 AMSELECT가 슬롯 상태 및 선택을 기기에 전달합니다. 세션 중에는 AMHEARTBEAT를 보냅니다. 실행 파일에 `--check-device`를 붙이면 CDC 버전과 HID 세션 연결을 확인하고 종료합니다. 이미 실행 중인 컴패니언은 이 검사 전에 종료하세요. 빌드는 `bash scripts/package.sh`, 단위 테스트는 `swift test`입니다. SwiftPM 중첩 샌드박스를 지원하지 않는 실행기에서는 `--disable-sandbox`를 덧붙입니다.

## 키 매핑

입력 ID와 기본 동작, 매핑 저장 방식, 다른 앱을 연결하는 절차는 [키 매핑과 앱 연동 가이드](docs/key-mapping.md)에 정리했습니다. 키보드 일러스트는 [제조사 제품 페이지](https://micro.diyshare.cn/)의 기기 배치를 참고해 제작했습니다.

## 기능 키와 상태 LED

| 컨트롤 | 기본 동작 |
| --- | --- |
| 노브 반시계 / 시계 | 이전 / 다음 앱 키맵 (고정) |
| 노브 클릭 | 포커스 기반 자동 전환 켬 / 끔 (전역) |
| 방향키 | 같은 작업공간에서 해당 방향의 이웃 패널로 이동 |
| 1–6 | 최근 세션 선택 |
| 7 | 현재 창에 새 워크스페이스 생성 |
| 8 / 9 | 현재 대화에 연결된 cmux Feed 권한 요청 한 건을 한 번 승인 / 거부 |
| 10 | 오른쪽 사이드 패널 열기 |
| 11 | 활성 터미널에 스페이스 |
| 12 | 현재 터미널의 저장된 대화를 오른쪽 분할에서 포크 |
| 13 | 활성 터미널에 엔터 |

앱 키맵은 cmux → Slack → Obsidian → T3 Code → Claude Desktop → ChatGPT / Codex 순서로 순환합니다. 노브 회전은 키맵 전환, 클릭은 자동 전환에 고정되며 변경 사항이 HUD에 잠깐 표시됩니다. 자동 전환의 초기값은 끔입니다. 켜면 지원 앱이 전면으로 올 때 그 앱의 키맵이 활성화됩니다. 다른 앱의 포커스는 마지막 키맵을 유지합니다. 터치는 전환에 사용하지 않습니다. cmux 이외의 키맵은 실행 중인 대상 앱에 macOS 키 입력을 보내며, macOS 손쉬운 사용 권한이 필요할 수 있습니다.

**키 매핑**에서 키보드 일러스트의 번호 키와 방향키를 선택해 cmux 동작 또는 터미널 단축키를 배정합니다. **저장**하면 적용되고 **기본값 복원**으로 선택한 컨트롤의 기본 동작을 되살릴 수 있습니다. 8·9번은 대상 요청을 특정할 수 있을 때 동작하고, 12번은 실행 중인 Codex의 경우 패널 TTY의 전경 프로세스가 쓰는 대화 기록에서 ID를 확인하고 cmux 복원 ID를 자동 등록·교정합니다. 자식 패널에서 다시 누르면 그 자식의 대화를 포크합니다. 다른 제공자는 cmux의 저장된 포크 명령을 사용합니다.

| 앱 표시등 | 의미 |
| --- | --- |
| 주황 | cmux가 작업공간 에이전트의 입력 요청을 보고함 |
| 하늘색 | 작업공간에 실행 중인 에이전트가 있음 |
| 보라 | 작업공간의 유효 상태가 완료(done) |
| 초록 | 현재 터미널 |
| 청회색 | 대기 |
| 회갈색 | 작업공간 상태 조회 실패 |
| 꺼짐 | 빈 슬롯 또는 연결 끊김 |

입력 요청, 실행, 완료 순서로 우선 표시합니다. 이 세 상태는 cmux의 `workspace status` 신호이므로 같은 작업공간의 슬롯에 함께 반영됩니다. 실기기 0.2.18에서는 선택한 5번 슬롯이 흰색으로 점멸했고, 작업공간 실행 중에는 파란색, 입력 대기에는 붉은색, 완료에는 초록색으로 점멸했습니다. 터미널별 포커스는 별도로 추적합니다. 실기기의 색과 점멸은 펌웨어가 슬롯 상태 코드와 선택 슬롯에 따라 표시합니다.

메뉴 막대 아이콘의 클릭과 macOS 접근성 동작 **슬롯 팝오버 열기**는 같은 네이티브 팝오버를 엽니다. 창 단위로만 탐색하는 접근성 도구는 `--show-slots`로 연 창에서 실제 상태 버튼에 접근할 수 있습니다.

이전 구현은 가상 T3 세션 여섯 개를 표시하는 데모, Basic 0.1.0 전용 USB 조회 코드, T3 0.1.7 경로 생성기로 구성되어 있었습니다. 아래는 그 시점의 기록입니다.

## Historical T3 prototype (superseded)
- The USB candidate button only enumerates macOS HID registry metadata (USB transport, 303A:8360 and vendor usage FF00/1). Candidate identity is not firmware compatibility. Do not send anything to a device solely because metadata matches.
- Probe encodes only documented version/status frames, but no code opens a device or writes USB reports. Before live enablement, positively identify the physical device/revision and the running protocol; implement bounded reply reassembly/request correlation and distinguish a verified reply from a Basic-style match. Then check LED behavior on isolated test hardware.
- T3 live adapter is not implemented: test-device desktop version must be pinned; evaluate documented authentication, local-only state subscription, opaque environment/thread IDs and exact router navigation. If no supported exact navigation hook exists at the pinned version, add a reviewed local T3-side change rather than keystroke injection or sidebar-index approximation. Do not pass auth tokens on a command line or extract them from existing processes.
- Live slot reassignment is deliberately not enabled. Freeze the physical slot-to-session assignment for each live attachment (expired slots do nothing); do not silently reuse them without an evidenced device render/arming protocol.
- The documented wire bytes are not yet proven against a vendor capture or against actual IOKit report ID handling. Do that before enabling live send/receive.
- Finder demo bundle: dist/MicroCompanion.app. It is a local development build, not notarized, and was not installed or GUI-tested by this task.

## Dormant read-only preflight
`USBProbe.swift` now implements a **not wired to UI, not run** read-only Basic transport path. It newly enumerates scoped USB vendor collections, requires exact descriptor SHA-256 + device USB location + reported USB revision, 64-byte metadata and exactly one match, plus explicit separate operator confirmation and an already known compatible Basic version. USB revision is not PCB proof. The transport only admits typed version/status requests, expects independently correlated replies, and aborts on malformed frames, timeout or version mismatch. No LED command can enter this path. No HID output was sent from the demo build.
The strict parser has manually authored wire fixtures, not a hardware/vendor capture. Numbered output report convention was cross-checked against libusb/hidapi's macOS implementation; hardware support for these conventions and response schema has not been verified. In particular, compare the recorded MAC/physical revision and descriptor from a known unit and use a test capture before exposing a call site.

Rebuild the Finder demo with `bash scripts/package.sh` (add `--disable-sandbox` only on the trusted executor which prohibits nested SwiftPM sandboxes). The script stages a debug bundle for local development.

## Dormant stock T3 0.1.7 navigation route
The Swift core can now construct the exact stock v0.1.7 native route from a pair of validated opaque environment/thread IDs. It rejects any other app version and all characters beyond ASCII RFC 3986 unreserved (with dot segments also refused); it does not receive arbitrary URLs, select an app, open URLs, or inspect installed software. The demo is offline and never opens routes. A future live integration must verify the target app bundle and exact version plus supported authentication/state, bind a hardware-confirmed active slot, and verify cold/warm launch and native routing on an isolated synthetic T3 session.
