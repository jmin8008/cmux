---
title: 핸드오프 — cmux 포크 개발과 남은 네이티브 검증 (2026-10-29)
type: handoff
date: 2026-10-29
author: jmin8008
status: active
issue:
tags: [handoff, jmin-fork, native-validation]
---
# 핸드오프 — cmux 포크 개발과 남은 네이티브 검증

> 한 줄 요약: 개발 환경·격리·V 로고와 4개 기능 코드를 준비했고, 설정 경고를 해결했다. 앱 바로가기 실행 오류와 창 분리·에이전트 화면의 수정 후 네이티브 검증이 남았다. 대상: 다음 작업자(실행).
> 기록 시점: 2026-10-29 13:42 KST. 사용자가 “여기까지 하고 인계 문서 작성”을 요청하여 구현·빌드·테스트를 중단했다. **사용자가 재개를 요청하기 전에는 아래 작업을 실행하지 않는다.**
> 이전 자료: [개발 상태](STATUS.md), [설계·결정 색인](../INDEX.md), [개발 환경 안내](../../jmin-development.md).

## 0. 재개 시 가장 먼저 볼 상태

전체 기능이 완료된 상태는 아니다. **소스 HEAD, 실제 빌드된 앱, 테스트 통과 상태가 서로 다르다.**

| 기능 | 브랜치 / 현재 HEAD | 실제 앱·검증 상태 | 다음 작업 |
|---|---|---|---|
| 공통 개발 환경 | `codex/dev` · `8ec0a0d03e` | `699e644174` 앱 빌드·실행·터미널 출력 확인. 최신 공통 V 로고는 이 기본 앱에 재빌드되지 않음 | 마지막에 기본 `jmin` 앱 재빌드·실행 |
| PRD1 화면 맥락 | `codex/browser-context` · `6de06006f7` | `4b3e5eb828` 앱 실행. 실제 클릭/문장 선택 → 지정 PTY 전달, 기존 입력 보존, Enter 미전송 확인 | 남은 경계 시나리오만 추가 검증 |
| PRD2 창 밖 분리 | `codex/drag-out-window` · `f17b77478c` | `b844fe58d9` 앱 실행. 실제 드래그 실패에서 콜백 초기화 누락 발견. 최신 수정은 회귀 테스트만 통과 | 최신 HEAD 재빌드 후 실제 드래그 재검증 |
| PRD3 에이전트 화면 | `codex/agent-workspace` · `afeca10f75` | `81985e00a8` 앱 빌드 실패. 타입 추론 수정은 축소 재현만 통과. 실행 가능한 PRD3 앱은 아직 없음 | 수정본 앱 빌드 → 실제 앱 호스트 테스트 → 그룹 화면 검증 |
| PRD4 바로가기 | `codex/quick-launch` · `9ee19ce42c` | `703adeea05` 앱 빌드·실행·PONG 확인. Calculator 바로가기 오류는 여전히 재현. 최신 HEAD는 **실패 회귀 테스트만 추가한 상태** | 앱 실행 오류 원인 확인·수정, 복원 탭 재사용·CLI 갱신 재검증 |

기능 브랜치를 서로 합치지 않았다. 원격 push, PR 생성, 병합, 설치된 stable 앱 교체는 하지 않았다.

### 작업 디렉터리와 미커밋 파일

기본 repo: `/Users/jgy/workplace/tmp/cmux`.

| 용도 | 경로 | 상태 |
|---|---|---|
| PRD1 | `/Users/jgy/workplace/tmp/cmux-worktrees/browser-context` | clean |
| PRD2 | `/Users/jgy/workplace/tmp/cmux-worktrees/drag-out-window` | clean |
| PRD3 | `/Users/jgy/workplace/tmp/cmux-worktrees/agent-workspace` | clean |
| PRD4 | `/Users/jgy/workplace/tmp/cmux-worktrees/quick-launch` | `docs/jmin-features/implementation/quick-launch-handoff.md` 수정 초안 미커밋 |
| 공통 빌드 전용 | `/Users/jgy/workplace/tmp/cmux-worktrees/build` | clean, detached `703adeea05` |

기본 repo의 미커밋 문서는 이 인계 문서, 갱신한 `INDEX.md`와 `implementation/STATUS.md`다. **이 인계 단계에서는 코드 수정·테스트·새 커밋을 하지 않았다.** 재개할 때 `git status`와 실제 HEAD를 먼저 확인하고, 미커밋 문서를 버리지 않는다.

## 1. 완료한 공통 작업

- Xcode **27.1 (27A9275)** 설치, 사용자 약관 동의·관리자 인증 완료, first-launch 상태 검사 통과. Metal Toolchain **27A266a** 설치 및 `scripts/setup.sh` 완료.
- Zig **0.16.0**, Rust **1.88.0 / 1.95.0** 및 양쪽 macOS target, pin된 GhosttyKit과 SwiftPM 캐시 준비. Go가 없어 Debug WireGuard는 저장소의 stub을 사용한다.
- 개발 앱 이름·bundle ID·socket·JSON/비밀 설정 경로를 태그별로 분리했다. JSON은 `~/.config/cmux-dev/jmin/`, 기능 앱은 `jmin.context`, `jmin.window`, `jmin.agents`, `jmin.launch` 하위 경로다.
- 원본 벡터의 `>`를 시계 방향 90도 회전한 **V 아이콘**을 Debug 10개 크기와 실행 중 light/dark 이미지 2개에 반영했다. `jmin-launch`의 실제 About 화면에서도 V를 확인했다. 원본: `design/jmin-dev-icon.svg`, 생성기: `scripts/generate-jmin-dev-icon.cjs`.
- 로컬 backend 실행이 원본 팀 credentials를 요구하던 문제(`dc12849f38`)와 optional legacy 설정 경로의 CLI 컴파일 오류(`699e644174`)를 수정하고 모든 기능 브랜치에 반영했다.
- 다음 빌드의 사전 정리가 아직 실행 중인 같은 태그 앱 리소스를 지우던 문제를 재현·수정했다(`444b97c96c` → `8ec0a0d03e`, 기능 브랜치에는 cherry-pick). 성공한 빌드의 교체 시점까지 기존 앱을 보존한다.

### 반복해서 나타나던 설정 경고 — 해결됨

cmux용 JSON이 실제로 `~/.config/ghostty/config`에 저장되어 있었다. Ghostty는 key=value 형식을 읽으므로 `{` 등 각 JSON 줄이 `unknown field` 경고를 만들었다.

원본 두 파일을 각각 `.backup-20261029-132306`으로 보존하고 다음 **7개 값만** `~/.config/cmux/cmux.json`으로 옮겼다. 기존 주석 168줄과 다른 값은 유지했다.

```text
terminal.copyOnSelect = false
terminal.autoResumeAgentSessions = true
terminal.agentHibernation.enabled = true
terminal.agentHibernation.idleSeconds = 300
terminal.agentHibernation.maxLiveTerminals = 12
app.confirmQuit = "always"
app.warnBeforeClosingTab = true
```

Ghostty 설정 검사 실패→통과, cmux 전역 JSON 검사 통과. **실행 중인 `jmin-launch`에서 재시작 없이 경고가 사라지는 것까지 확인했다.** 이 설정 복구를 다시 수행하거나 개발 JSON으로 복제하지 않는다.

설정 격리의 의도된 경계: 프로젝트 설정과 standalone `~/.config/ghostty/`는 현재 개발 문서대로 공유 입력이다. cmux JSON과 cmux 전용 App Support Ghostty 설정은 분리되어 있다. 완전한 Ghostty 격리는 이번 복구에 포함하지 않았다.

## 2. 기능별 남은 작업과 검증 근거

### PRD4 — 앱 바로가기 오류부터 해결

**확인된 현상:** Calculator 앱을 선택·저장하는 UI는 동작하지만, 이전 앱과 최신 빌드 `703adeea05` 모두 바로가기 클릭 시 “앱을 열 수 없습니다” 오류가 난다. bookmark 검사에서 `stale=false`, 저장 URL과 일치, bundle ID도 일치했다.

**가설과 사실의 경계:** `Sources/QuickLaunch.swift`의 `openApp`은 기존 앱의 `running.activate()`가 false이면 즉시 실패한다. 이 경우를 회귀 테스트로 재현했지만, 실제 Calculator 오류가 정확히 이 분기에서 났다는 계측은 아직 없다. 콜드 실행의 `NSWorkspace.openApplication` 오류도 구분해야 한다.

- `9ee19ce42c`: `tests/test_quick_launch_app_activation.py` 추가. **3개 중 1개 의도된 실패, 수정 미적용.** 이 HEAD를 전체 green이라고 보고하지 않는다.
- 다음 수정 후보: `activate()` 실패 때 검증된 동일 URL을 `NSWorkspace.openApplication`으로 열되 새 앱 인스턴스를 강제하지 않는다. 필요하면 DEBUG에 NSError domain/code만 기록하여 실제 실패 분기를 구분한다.
- `703adeea05`에는 복원된 `DeferredBrowserPanel`을 기존 탭 후보에 포함하는 수정과 UI 변경 후 `externalTopologyDidChange()` 호출이 들어 있다. 앞선 회귀 테스트 5개+2개 통과, 수정본 네이티브 빌드·PONG 확인. **수정 후 실제 복원 탭 재사용과 UI/CLI 목록 일치 재검증은 미실행.**
- 기존 검증: 저장소 설정 테스트 9개, 정적 검사 17/17, 9개 언어 parity 검사 통과. 정상 titlebar의 알림→바로가기→+ 순서, 잘못된 URL 거부, 설치 앱 선택·저장, 실제 V 아이콘을 확인했다.
- 남은 UI: cold/warm 앱 열기, 기존 탭 재사용·동일 URL count, 편집/삭제/drag 재정렬, 재시작 저장 복원, fullscreen/minimal 및 키보드 접근성.
- 상세: [PRD4 작업 트리 인계](/Users/jgy/workplace/tmp/cmux-worktrees/quick-launch/docs/jmin-features/implementation/quick-launch-handoff.md).

### PRD2 — 수정본을 실제 드래그로 확인

실제 드래그에서 기존 `TabManager`의 registry를 채택하는 앱 시작 경로가 완료 콜백 등록을 건너뛰는 문제를 찾았다. `833e0a9e1d` 재현 테스트 실패 → `f17b77478c` 공통 등록 함수 수정 후 **2/2 통과**, 정적 검사 **17/17**.

현재 실행 중인 앱은 수정 전 `b844fe58d9`이다. **재빌드 없이 재검증하면 같은 실패를 다시 보게 된다.** Escape로 취소했을 때 기존 terminal panel/TTY/PID가 유지되는 것은 수정 전 앱에서 확인했다.

남은 확인: 실제 mouse-up이 release로 분류되는지, 새 창 위치, 터미널 PID/PTY/출력 유지, 동일 WKWebView 상태, 파일 preview, 다른 cmux 창에 정상 drop, 전체 workspace/sidebar drag와 layout 유지. `cmuxTests/DragOutWindowTransferTests.swift`의 실제 앱 호스트 테스트 4개는 아직 실행하지 않았다.

`vendor/bonsplit`은 로컬 커밋 **`3316685ac4170ddab29b85f56c136f98d22a58a3`**을 사용한다. 아직 원격에 게시하지 않았다. 복구 bundle은 기본 repo의 `.git/jmin-feature-coordination/drag-out-window-bonsplit.bundle`에 있다. 이번 콜백 보완은 AppDelegate만 수정했다.

상세: [PRD2 작업 트리 인계](/Users/jgy/workplace/tmp/cmux-worktrees/drag-out-window/docs/jmin-features/implementation/drag-out-window-handoff.md).

### PRD3 — 첫 성공 빌드와 실제 세션 검증 필요

첫 네이티브 빌드 `81985e00a8`은 `Sources/Panels/TerminalPanelView.swift:102`의 `failed to produce diagnostic for expression`으로 실패했다. `afeca10f75`는 선택적 `@MainActor` 클로저 삼항식을 명시적 타입의 지역 변수로 분리한다. 앱의 Swift 5 언어 모드 축소 재현에서 실패→통과, Swift 6 모드에서도 수정본 통과. **실제 앱 재빌드는 아직 하지 않았다.**

구현에는 부모/팀원/서브에이전트 대화·도구·원본 터미널 보기, 같은 PTY를 유지하는 renderer lease, 종료·교체된 세션에 대한 표시/입력 해제, 실제 Claude Teams/Codex parent 관계 처리가 포함된다. 화면 그룹 ID를 실제 입력 세션 ID로 대체하지 않는다.

기존 검증: 웹 137개 테스트 + 46개 assertion script, 타입 검사·웹 빌드, 정적 17/17, 복원 설정 패키지 4/4 통과. 실제 앱 호스트 테스트와 컴파일된 CLI의 Teams 통합 검증은 **미실행**이다.

남은 실제 테스트: `AgentWorkspacePresentationTests` 4, `AgentWorkspaceRendererLeaseTests` 14 사례, `AgentWorkspaceInputBindingTests` 2, `CmuxAgentChatConfigTests` 30 예상. 실제 xcresult로 실행 개수를 확정한다. 네이티브 그룹 UI에서 부모 입력, 팀원 선택, trace-only, 원본 터미널 PID/PTY 유지, 종료/같은 PTY 재바인딩 후 입력 차단을 확인한다.

상세: [PRD3 작업 트리 인계](/Users/jgy/workplace/tmp/cmux-worktrees/agent-workspace/docs/jmin-features/implementation/agent-workspace-handoff.md).

### PRD1 — 기본 네이티브 흐름 확인, 경계 검증만 남음

`4b3e5eb828` 앱에서 실제 클릭/문장 drag를 등록된 PTY로 전달했다. 맥락 3회, bracketed paste, 기존 `existing draft ` 입력 유지, **CR/Enter 0개**를 확인했다. 원래 버튼 동작 억제, iframe 포인터 차단, Escape 후 iframe 조작 복원, navigation/reload 시 선택 해제도 확인했다.

기존 검증: JS 9개(실제 Chromium 16개 점검 포함), Swift 모델 5개, 정적 17/17 및 localization 통과. 마지막 `6de06006f7`은 실제 검증 기록이다. 자체 probe PID/registry/workspace는 정리했다.

남은 경계: 여러 에이전트의 대상 변경/모호성, target 종료·이동과 비동기 캡처 경합, zoom/scroll 좌표, Design Mode/React Grab 상호 전환. 1차 범위는 내부 HTML/localhost의 클릭·문장 선택이며 PDF/Markdown 별도 뷰어·사각형 영역·이미지는 제외한 확정 설계다.

상세: [PRD1 작업 트리 인계](/Users/jgy/workplace/tmp/cmux-worktrees/browser-context/docs/jmin-features/implementation/browser-context-handoff.md).

## 3. 다음 작업 순서와 명령

사용자가 재개를 요청한 다음 순서다. 추가 승인 질문 없이 확정 범위에서 진행하되, 기능 채택 전 서로 병합하지 않는다.

1. 각 worktree의 HEAD·미커밋 문서와 실제 실행 프로세스를 확인한다.
2. **PRD4** 실패 테스트와 실제 앱 실행 실패를 해결하고 같은 태그로 재빌드한다. 복원 탭 재사용·CLI 갱신도 검증한다.
3. **PRD3** `afeca10f75` 또는 후속 HEAD를 빌드하여 첫 성공을 확인한다. CLI/앱 호스트 테스트와 그룹 UI 검증을 이어간다.
4. **PRD2** `f17b77478c` 또는 후속 HEAD를 빌드하고 실제 drag 및 앱 호스트 테스트를 수행한다.
5. PRD1의 남은 경계를 확인하고, 기본 `codex/dev`를 최신 V 아이콘으로 재빌드·실행한다.
6. 실제 결과를 각 기능 인계 문서와 이 문서의 후속 인계에 기록한다. 채택할 기능을 정하기 전에는 브랜치를 통합하지 않는다.

### 태그 빌드

**한 번에 하나의 빌드만** 공통 체크아웃에서 실행한다. 빌드·테스트 중에는 이 checkout의 branch/submodule을 바꾸지 않는다.

```sh
source /Users/jgy/workplace/tmp/cmux-toolchains/env.sh
cd /Users/jgy/workplace/tmp/cmux-worktrees/build
git status --short
git switch --detach codex/agent-workspace
git submodule update --init vendor/bonsplit
CMUX_RELOAD_APP_EMIT_MODULE=1 ./scripts/dev-jmin-agents.sh --launch --no-global-cli-links
CMUX_TAG=jmin-agents ./scripts/cmux-debug-cli.sh ping
```

`CMUX_RELOAD_APP_EMIT_MODULE=1`은 후속 테스트 import에 필요한 `cmux_DEV.swiftmodule`을 남긴다. 첫 테스트 빌드가 빨라진다는 보장은 없다. 테스트까지 필요하지 않은 기존 `reload.sh` 기본 경로는 이 모듈을 생략한다.

| 브랜치 | wrapper | CLI tag |
|---|---|---|
| `codex/dev` | `./scripts/dev-jmin.sh` | `jmin` |
| `codex/browser-context` | `./scripts/dev-context.sh` | `jmin-context` |
| `codex/drag-out-window` | `./scripts/dev-jmin-window.sh` | `jmin-window` |
| `codex/agent-workspace` | `./scripts/dev-jmin-agents.sh` | `jmin-agents` |
| `codex/quick-launch` | `./scripts/dev-jmin-launch.sh` | `jmin-launch` |

모든 명령에 동일 toolchain 환경을 적용한다. 시스템 `xcode-select`는 CLT일 수 있으므로 helper의 `DEVELOPER_DIR`가 필요하다. CLI도 `CMUX_DERIVED_DATA`가 있어야 공통 캐시의 태그 앱을 찾는다. bare `xcodebuild`, 무태그 앱 실행, `/tmp/cmux-cli`, global CLI link 교체는 사용하지 않는다.

공통 cache: `~/Library/Developer/Xcode/DerivedData/cmux-jmin-build`. SwiftPM: `/Users/jgy/workplace/tmp/cmux-toolchains/SourcePackages`. 별도 checkout별 cold cache를 다시 만들 필요는 없다. `files.cmux.com` DNS 실패가 재발하면 컴파일 성공과 패키징 실패를 구분한다.

### 실제 앱 호스트 테스트 — 준비만 됨

실행기는 `/tmp/cmux-jmin-focused-native/runner.py`, 절차는 같은 폴더 `README.md`에 있다. **clone/settings/build/run 어느 단계도 아직 실행하지 않았다.** 실제 테스트 소스를 선택하며 production stub으로 대체하지 않는다. 별도 DerivedData를 APFS 복제하고 태그·설정·소켓·테스트 홈을 분리한다.

```sh
# 공통 build checkout을 원하는 기능 HEAD에 맞춘 뒤, 테스트가 끝날 때까지 유지
python3 /tmp/cmux-jmin-focused-native/runner.py plan --profile agents
python3 /tmp/cmux-jmin-focused-native/runner.py clone --profile agents
python3 /tmp/cmux-jmin-focused-native/runner.py settings --profile agents
python3 /tmp/cmux-jmin-focused-native/runner.py build --profile agents
python3 /tmp/cmux-jmin-focused-native/runner.py run --profile agents
```

PRD2는 `--profile window`. `settings`의 실제 Xcode 확장 결과 확인이 선행 조건이며, 아직 검증되지 않은 runner다. 실패하면 검사 조건을 우회하지 말고 runner를 수정한다. 테스트가 UI를 사용하므로 수동 CUA 검증과 동시에 실행하지 않는다. xcresult의 **실제 테스트 개수와 실패**를 읽고, 0개 실행을 성공으로 세지 않는다.

PRD3의 `tests/test_cli_agent_workspace_teams.py`에는 `CMUX_CLI_BIN`으로 실제 태그 앱 CLI를 전달한다. 준비된 runner의 `cli --profile agents --cli <실제 CLI 경로>`가 이를 처리한다. 사용자 에이전트 대신 자체 Unix socket과 가짜 로컬 공급자를 쓰는 테스트다.

더 풍부한 UI fixture: `/tmp/cmux-jmin-agents-native-qa-xr3u18w2/PLAN.md`. **아직 provider/session을 시작하지 않았다.** plan의 실제 session/PTY marker와 cleanup 절차를 따른다.

## 4. 중단 시 남긴 프로세스·QA 데이터

- 진행 중인 Xcode 빌드나 테스트 프로세스는 없다. 하위 에이전트도 중단·보고를 완료했다.
- 개발 앱은 사용 가능한 상태로 두었다: `jmin-launch` PID 10009, `jmin-window` PID 16354, `jmin-context` PID 55038(13:42 관찰값; 재개 시 다시 조회).
- 사용자 stable cmux PID 51846은 종료·교체·재실행하지 않았다. 앞으로도 해당 앱은 건드리지 않는다.
- `jmin-launch` 개발 설정에 `QA Launch A`, `QA Calculator`, `QA Launch B`가 남아 있다. QA 브라우저 A와 Calculator 오류 popover도 남을 수 있다. 후속 검증 후 **해당 QA 항목만** 정리한다.
- Calculator PID 95490은 사용자 실행일 가능성이 있어 내용 변경·종료하지 않았다.
- 자체 localhost fixture 서버 PID 9597은 사용자 중단 요청에 맞춰 종료했다. 재개 시 필요하면 `python3 -m http.server 18765 --bind 127.0.0.1 --directory /tmp/cmux-jmin-smoke`로 다시 실행한다. 다른 포트의 서버를 종료하지 않는다.
- PRD1 자체 raw-input probe/registry/QA workspace는 이미 정리했다. PRD2의 QA terminal은 남아 있다. 재빌드 뒤에는 새 marker로 PID/TTY 보존을 비교한다.

## 5. 근거와 복구 자료

임시 파일 소실에 대비해 아래 로컬 Git metadata 폴더에 실행기·fixture·검증 JSON·주요 빌드 로그 21개 항목을 복사했다. 앱/사용자 설정 전체를 복제하지 않았다.

```text
/Users/jgy/workplace/tmp/cmux/.git/jmin-feature-coordination/handoff-20261029/
```

`manifest.json`에 보존 항목이 있다. `/tmp` 자료가 없어졌다면 필요한 폴더를 원래 `/tmp/<이름>`으로 복원한다. fixture와 runner에는 원래 절대 경로가 포함되어 있다. 이 자료는 **로컬에만 있으며 Git push에 포함되지 않는다.**

| 근거 | 보존본의 파일/폴더 |
|---|---|
| 반복 설정 경고 복구 | `config-repair-receipt.json`, `cmux-user-config-before.log` |
| PRD1 실제 raw PTY 입력 | `cmux-context-native-acceptance-input.json` |
| PRD2 실제 실패·Escape·red/green | `cmux-prd2-native-qa/` |
| PRD3 컴파일러 축소 재현 | `cmux-native-view-initializer-repro.sh`, probe Swift 2개 |
| PRD4 앱 활성화 의도된 실패 | `cmux-quick-launch-activation-red.log` |
| PRD4 수정 전 stale 목록/새 앱 초기 목록 | `cmux-qa-launch-after-reuse.json`, `cmux-qa-launch-fixed-before.json` |
| 마지막 PRD4 성공 빌드 | `cmux-reload-jmin-launch.log` |
| PRD2 컴파일·실행 성공 | `cmux-reload-jmin-window.log`, `cmux-window-native-retry.log` |
| PRD3 실패 빌드 | `cmux-reload-jmin-agents.log`, `cmux-agents-native-build.log` |
| 아직 실행하지 않은 native runner/fixture | `cmux-jmin-focused-native/`, `cmux-jmin-agents-native-qa-xr3u18w2/` |

## 6. 확정 사항과 남은 판단

확정 사항은 다시 묻지 않는다: 기능별 독립 브랜치/앱, 원본 stable 앱 보호, V 아이콘, PRD1 자동 대상 연결·삽입만 수행·수동 Enter, PRD2 세션/레이아웃 유지, PRD3 실제 세션 정체성 유지, PRD4 앱 공통 클릭 목록과 현재 workspace 재사용.

현재 구현을 재개하기 위한 새 사용자 결정은 없다. 향후 기능을 실제 사용한 뒤 **어떤 기능을 `codex/dev`에 채택할지**가 남은 제품 판단이다. 원격 공유 시에는 PRD2 Bonsplit 로컬 커밋을 접근 가능한 원격에도 게시해야 한다.
