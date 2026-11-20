# AI Micro 0.2.96 macOS 호환성

분석 대상은 제공된 AI Micro.app의 arm64 실행 파일 ai-micro-companion이다. 실행 파일의 SHA-256은 `4d5aec1a699dffa9d7db1013e848bde74688d07c5c5b1d098d89be8df8025b32`이다.

- Rust 함수 config::default_bindings (0x1003a1930)가 참조하는 44,967바이트의 JSON에서 macOS 일반 단축키 표를 추출했다. Claude Desktop 기본 키는 이 표를 사용한다. 이전에 저장한 사용자 매핑은 우선한다.
- Codex Desktop의 기본 키는 설치된 ChatGPT 26.1111.71704의 `codex-micro-layout`을 기준으로 한다. 기본 결합 마이크 키캡은 ACT10에서 누름·해제를 처리하고 ACT11은 무시한다. Keyberth에서 7번은 ChatGPT가 제공하는 `codex://dots` 경로를 열고, 12번은 새 대화를 시작한다. 노브는 앱별 매핑을 따른다. 포크는 대화 제목 메뉴에서 현재 작업공간을 선택한다. 계획 모드는 Codex의 사용자 키 바인딩을 읽는다.
- 원본은 일반 단축키와 펌웨어의 Codex 네이티브 모드를 구분한다. Keyberth는 노브 입력을 계속 받기 위해 Universal Agent의 generic 모드를 사용한다. 펌웨어를 Codex에 양도할 때의 네이티브 입력 및 조명은 이 프로필의 검증 범위 밖이다.
- claude::HookServer::start (0x1003965ec), claude::Hub::snapshot (0x10039228c), platform::open_claude_session (0x1002bdf9c)과 로컬 세션 링크를 확인했다. Keyberth는 자체 Claude Code 훅에서 상태와 요청을 읽어 슬롯에 표시하며 Desktop의 claude://claude.ai/epitaxy/local_… 링크를 사용한다.
- Keyberth의 Claude Code 슬롯은 최근 활동순이다. 최근 세션 화면에서 소스 필터, 슬롯별 고정·해제, 복수 권한 요청 중 대상 선택을 제공한다. 비교 근거는 첨부 바이너리와 번들 UI의 정적 분석이다.

[키별 기본값과 설정](key-mapping.md)

## 세션 표시 근거

동일 바이너리의 파일 오프셋 0xb4e311에서 Brotli 압축된 index-B1zr5XWo.js를 해제했다. DeepSeek 연동 안내는 실행 중 파랑, 승인 대기 주황, 일반 입력 대기 흰색, 아직 보지 않은 턴 완료 초록, 오프라인 소등으로 설명한다. Cursor와 ZCode 안내도 초록을 읽지 않은 완료로 한정한다. Keyberth는 이 색상 의미를 공통 기본값으로 사용한다. RGB 수치와 점멸 주기는 해당 안내에서 지정하지 않는다.
