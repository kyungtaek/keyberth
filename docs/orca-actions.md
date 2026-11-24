# Orca 초기 프리셋과 기능 목록

Orca for macOS 1.4.272의 기본 키 배정 레지스트리 기준입니다. 플러그인과 사용자가 만든 Quick Command는 설치 환경마다 다릅니다. 기본 단축키가 없는 기능은 Orca 설정 → Shortcuts에서 지정할 수 있습니다. ‘Codex 새 탭’은 Orca의 내장 CLI로 현재 워크스페이스에 Codex를 열고 포커스하며, 별도 단축키 설정 없이 동작합니다.

| 입력 | 초기 배정 |
|---|---|
| 1~6 | 글로벌 배정 상속 (기본값은 통합 최근 세션) |
| 7 / 8 / 9 | 전체 검색 / 에이전트 대시보드 / 워크스페이스 보드 |
| 10 / 11 / 12 / 13 | 오른쪽 사이드바 / Orca 받아쓰기 / 새 에이전트 탭 / Enter |
| 노브 왼쪽 / 오른쪽 / 클릭 | 이전 탭 / 다음 탭 / 플로팅 터미널 |
| 방향키 위 / 아래 | 이전 / 다음 워크트리 |
| 방향키 왼쪽 / 오른쪽 | 이전 / 다음 터미널 패널 |

[버전별 공식 명령 정의](https://github.com/stablyai/orca/tree/v1.4.272/src/shared/keybindings)

두 번호 선택 기능은 각각 1~9를 별도 항목으로 제공합니다. 아래 단축키는 Mac 기본값이며 Mod는 Command입니다.

## 워크스페이스 · 전역

| 기능 | Orca 명령 | Mac 기본 단축키 |
|---|---|---|
| 파일로 이동 | `worktree.quickOpen` | Mod+P |
| 설정 열기 | `app.settings` | Mod+Comma |
| 강제 새로고침 | `app.forceReload` | Mod+Shift+R |
| 전체 검색 | `worktree.palette` | Mod+K |
| 이전 워크트리 | `worktree.navigateUp` | Mod+Shift+ArrowUp |
| 다음 워크트리 | `worktree.navigateDown` | Mod+Shift+ArrowDown |
| 워크트리 만들기 | `workspace.create` | Mod+N, Mod+Shift+N |
| 워크트리 이름 바꾸기 | `workspace.rename` | Mod+Alt+R |
| Delete Selected Workspace | `workspace.delete` | Mod+Shift+Backspace |
| 워크스페이스 보드 전환 | `workspace.openBoard` | 미지정 |
| 에이전트 대시보드 전환 | `dashboard.toggle` | 미지정 |
| 워크스페이스 1–9 선택 | `workspace.selectByIndex` | Mod+1 |
| 받아쓰기 | `voice.dictation` | Mod+E |
| 작업 열기 | `view.tasks` | 미지정 |
| 플러그인 열기 | `view.plugins` | Mod+Alt+X |
| 사이드바 전환 | `sidebar.left.toggle` | Mod+B |
| 오른쪽 사이드바 전환 | `sidebar.right.toggle` | Mod+L |
| 탐색기 표시 | `sidebar.explorer.toggle` | Mod+Shift+E |
| 검색 표시 | `sidebar.search.toggle` | Mod+Shift+F |
| 소스 제어 표시 | `sidebar.sourceControl.toggle` | Mod+Shift+G |
| 체크 표시 | `sidebar.checks.toggle` | 미지정 |
| 포트 표시 | `sidebar.ports.toggle` | Mod+Shift+I |
| 절전 중인 워크스페이스 표시 전환 | `sidebar.sleepingWorkspaces.toggle` | 미지정 |
| 워크트리 목록에 포커스 | `sidebar.focusWorktreeList` | Mod+Shift+0 |
| 플로팅 터미널 전환 | `floatingTerminal.toggle` | Mod+Alt+A |
| 플로팅 워크스페이스 패널 최대화 | `floatingWorkspace.maximize` | Mod+Alt+Shift+A |
| 플로팅 워크스페이스 패널 최소화 | `floatingWorkspace.minimize` | 미지정 |
| 확대 | `zoom.in` | Mod+Equal, Mod+Shift+Plus, Mod+NumpadAdd |
| 축소 | `zoom.out` | Mod+Minus, Mod+NumpadSubtract |
| 크기 재설정 | `zoom.reset` | Mod+0 |
| 워크트리 기록 뒤로 | `worktree.history.back` | Mod+Alt+ArrowLeft |
| 워크트리 기록 앞으로 | `worktree.history.forward` | Mod+Alt+ArrowRight |
| 리뷰 노트를 에이전트에 보내기 | `sourceControl.sendReviewNotes` | 미지정 |
| 모든 프로젝트 접기 / 펼치기 | `sidebar.projects.toggleCollapse` | Mod+Alt+P |
| 하위 워크스페이스 전환 | `sidebar.childWorkspaces.toggle` | 미지정 |

## 탭

| 기능 | Orca 명령 | Mac 기본 단축키 |
|---|---|---|
| 새 터미널 탭 | `tab.newTerminal` | Mod+T |
| 새 에이전트 탭(기본 에이전트) | `tab.newAgent` | Mod+Alt+T |
| 새 브라우저 탭 | `tab.newBrowser` | Mod+Shift+B |
| 오른쪽 분할에 새 브라우저 탭 | `tab.newBrowserSplitRight` | Mod+Alt+B |
| 새 모바일 에뮬레이터 탭 | `tab.newSimulator` | Mod+Alt+Shift+E |
| 새 Markdown 탭 | `tab.newMarkdown` | Mod+Shift+M |
| Markdown 탭 열기 | `tab.openMarkdown` | Mod+Shift+O |
| 활성 탭 닫기 | `tab.close` | Mod+W |
| 모든 편집기 탭 닫기 | `tab.closeAll` | Mod+Alt+W |
| 활성 탭 이름 바꾸기 | `tab.rename` | Mod+R |
| 닫은 탭 다시 열기 | `tab.reopenClosed` | Mod+Shift+T |
| 활성 탭을 왼쪽으로 이동 | `tab.moveLeft` | 미지정 |
| 활성 탭을 오른쪽으로 이동 | `tab.moveRight` | 미지정 |

## 탭 이동

| 기능 | Orca 명령 | Mac 기본 단축키 |
|---|---|---|
| 다음 탭(같은 유형) | `tab.nextSameType` | Mod+Alt+BracketRight |
| 이전 탭(같은 유형) | `tab.previousSameType` | Mod+Alt+BracketLeft |
| 다음 탭(모든 유형) | `tab.nextAllTypes` | Mod+Shift+BracketRight |
| 이전 탭(모든 유형) | `tab.previousAllTypes` | Mod+Shift+BracketLeft |
| 최근 사용한 이전 탭 | `tab.previousRecent` | Ctrl+Tab |
| 다음 터미널 탭 | `tab.nextTerminal` | Ctrl+PageDown |
| 이전 터미널 탭 | `tab.previousTerminal` | Ctrl+PageUp |
| 탭 1–9 선택 | `tab.selectByIndex` | Ctrl+1 |

## 빠른 명령

| 기능 | Orca 명령 | Mac 기본 단축키 |
|---|---|---|
| 빠른 명령어 메뉴 전환 | `tab.openQuickCommandsMenu` | 미지정 |

## 브라우저

| 기능 | Orca 명령 | Mac 기본 단축키 |
|---|---|---|
| 브라우저에서 찾기 | `browser.find` | Mod+F |
| 브라우저에서 뒤로 이동 | `browser.back` | Mod+BracketLeft |
| 브라우저에서 앞으로 이동 | `browser.forward` | Mod+BracketRight |
| 브라우저 기록 표시 | `browser.showHistory` | Mod+Y |
| 브라우저 페이지 새로고침 | `browser.reload` | Mod+R |
| 브라우저 페이지 강제 새로고침 | `browser.hardReload` | Mod+Shift+R |
| 브라우저 주소 표시줄에 포커스 | `browser.focusAddressBar` | Mod+L |
| 페이지 요소 가져오기 | `browser.grabElement` | Mod+C |
| 페이지 요소에 주석 달기 | `browser.annotateElement` | Mod+Shift+C |

## 편집기

| 기능 | Orca 명령 | Mac 기본 단축키 |
|---|---|---|
| 편집기에서 찾기 | `editor.find` | Mod+F |
| 편집기에서 바꾸기 | `editor.replace` | Mod+Alt+F |
| 파일 저장 | `editor.save` | Mod+S |
| Markdown 미리보기 표시 | `editor.markdownPreview` | Mod+Shift+V |
| 단어 줄 바꿈 전환 | `editor.toggleWordWrap` | Alt+Z |
| 변경 사항 보기 전환 | `editor.toggleChangesView` | 미지정 |
| 컨텍스트 복사 | `editor.copyContext` | Mod+Alt+C |
| 이전 변경으로 이동 | `editor.previousChange` | Shift+F7 |
| 다음 변경으로 이동 | `editor.nextChange` | F7 |
| 리뷰 노트 추가 | `editor.addReviewNote` | Mod+Shift+A |

## 파일 탐색기

| 기능 | Orca 명령 | Mac 기본 단축키 |
|---|---|---|
| 파일 작업 실행 취소 | `fileExplorer.undo` | Mod+Z |
| 파일 작업 다시 실행 | `fileExplorer.redo` | Mod+Shift+Z |
| 파일 경로 복사 | `fileExplorer.copyPath` | Mod+Alt+C |
| 파일 상대 경로 복사 | `fileExplorer.copyRelativePath` | Mod+Alt+Shift+C |
| 파일 삭제 | `fileExplorer.delete` | Mod+Backspace, Delete |

## 설정

| 기능 | Orca 명령 | Mac 기본 단축키 |
|---|---|---|
| 설정 검색 | `settings.search` | Mod+F |

## 터미널 패널

| 기능 | Orca 명령 | Mac 기본 단축키 |
|---|---|---|
| 터미널 선택 영역 복사 | `terminal.copySelection` | Mod+C |
| 터미널 텍스트 모두 선택 | `terminal.selectAll` | Mod+A |
| 터미널에 붙여넣기 | `terminal.paste` | Mod+V |
| 활성 창 검색 | `terminal.search` | Mod+F |
| 활성 창 지우기 | `terminal.clear` | 미지정 |
| 다음 창에 포커스 | `terminal.focusNextPane` | Mod+BracketRight |
| 이전 창에 포커스 | `terminal.focusPreviousPane` | Mod+BracketLeft |
| 창 크기 균등화 | `terminal.equalizePaneSizes` | 미지정 |
| 창 확장/접기 | `terminal.expandPane` | Mod+Shift+Enter |
| 제목 설정… | `terminal.setTitle` | 미지정 |
| 창 제목 지우기 | `terminal.clearPaneTitle` | 미지정 |
| 세션 ID 복사 | `terminal.copySessionId` | 미지정 |
| 활성 창 닫기 | `terminal.closePane` | Mod+W |
| 터미널 오른쪽으로 분할 | `terminal.splitRight` | Mod+D |
| 터미널 아래로 분할 | `terminal.splitDown` | Mod+Shift+D |
| 입력 소스/언어 전환(네이티브) | `terminal.switchInputSource` | 미지정 |

## 대화

| 기능 | Orca 명령 | Mac 기본 단축키 |
|---|---|---|
| 채팅에서 찾기 | `chat.find` | Mod+F |
| 채팅 UI와 터미널 간 전환 | `terminal.toggleNativeChat` | Mod+Shift+J |

## 봇

| 기능 | Orca 명령 | Mac 기본 단축키 |
|---|---|---|
| Back to Items | `botItem.back` | Mod+BracketLeft |
| 이전 항목 | `botItem.previous` | Mod+Alt+ArrowUp |
| 다음 항목 | `botItem.next` | Mod+Alt+ArrowDown |

## 에이전트 실행

| 기능 | Orca 명령 | Mac 기본 단축키 |
|---|---|---|
| Claude 새 탭 | `tab.newAgent.claude` | 미지정 |
| Claude Agent Teams 새 탭 | `tab.newAgent.claude-agent-teams` | 미지정 |
| CodeBuddy 새 탭 | `tab.newAgent.codebuddy` | 미지정 |
| OpenClaude 새 탭 | `tab.newAgent.openclaude` | 미지정 |
| Codex 새 탭 | `tab.newAgent.codex` | 미지정 |
| Devin 새 탭 | `tab.newAgent.devin` | 미지정 |
| Ante 새 탭 | `tab.newAgent.ante` | 미지정 |
| Trae 새 탭 | `tab.newAgent.trae` | 미지정 |
| Muse 새 탭 | `tab.newAgent.muse` | 미지정 |
| DeepSeek Harness 새 탭 | `tab.newAgent.dsh` | 미지정 |
| ZCode 새 탭 | `tab.newAgent.zcode` | 미지정 |
| Autohand Code 새 탭 | `tab.newAgent.autohand` | 미지정 |
| OpenCode 새 탭 | `tab.newAgent.opencode` | 미지정 |
| OpenCode 2 새 탭 | `tab.newAgent.opencode2` | 미지정 |
| MiMo Code 새 탭 | `tab.newAgent.mimo-code` | 미지정 |
| Pi 새 탭 | `tab.newAgent.pi` | 미지정 |
| OMP 새 탭 | `tab.newAgent.omp` | 미지정 |
| Prime Agent 새 탭 | `tab.newAgent.prime-agent` | 미지정 |
| Qoder CLI 새 탭 | `tab.newAgent.qoder` | 미지정 |
| Qoder CLI China 새 탭 | `tab.newAgent.qoder-cn` | 미지정 |
| Gemini 새 탭 | `tab.newAgent.gemini` | 미지정 |
| Antigravity 새 탭 | `tab.newAgent.antigravity` | 미지정 |
| Aider 새 탭 | `tab.newAgent.aider` | 미지정 |
| Goose 새 탭 | `tab.newAgent.goose` | 미지정 |
| Amp 새 탭 | `tab.newAgent.amp` | 미지정 |
| Kilocode 새 탭 | `tab.newAgent.kilo` | 미지정 |
| Kiro 새 탭 | `tab.newAgent.kiro` | 미지정 |
| Charm 새 탭 | `tab.newAgent.crush` | 미지정 |
| Auggie 새 탭 | `tab.newAgent.aug` | 미지정 |
| Cline 새 탭 | `tab.newAgent.cline` | 미지정 |
| Codebuff 새 탭 | `tab.newAgent.codebuff` | 미지정 |
| Freebuff 새 탭 | `tab.newAgent.freebuff` | 미지정 |
| Command Code 새 탭 | `tab.newAgent.command-code` | 미지정 |
| Continue 새 탭 | `tab.newAgent.continue` | 미지정 |
| Cursor 새 탭 | `tab.newAgent.cursor` | 미지정 |
| Droid 새 탭 | `tab.newAgent.droid` | 미지정 |
| Kimi 새 탭 | `tab.newAgent.kimi` | 미지정 |
| Mistral Vibe 새 탭 | `tab.newAgent.mistral-vibe` | 미지정 |
| Qwen Code 새 탭 | `tab.newAgent.qwen-code` | 미지정 |
| Rovo Dev 새 탭 | `tab.newAgent.rovo` | 미지정 |
| Hermes 새 탭 | `tab.newAgent.hermes` | 미지정 |
| OpenClaw 새 탭 | `tab.newAgent.openclaw` | 미지정 |
| GitHub Copilot 새 탭 | `tab.newAgent.copilot` | 미지정 |
| Grok 새 탭 | `tab.newAgent.grok` | 미지정 |
| Jcode 새 탭 | `tab.newAgent.jcode` | 미지정 |
