---
title: PRD3 에이전트 작업 화면 구현 인계
type: handoff
date: 2026-10-29
author: Codex
status: active
issue:
tags: [prd3, agent-workspace, implementation]
---
# PRD3 구현 인계

> 한 줄 요약: 메인 대화와 입력을 유지하는 그룹 화면·실제 하위/팀 관계·Teams 자동 진입을 연결했으며, 같은 세션의 native renderer를 그룹에 표시하는 경로를 구현했으며 앱 검증은 진행 전이다. 대상: 사람·후속 개발 에이전트.

## 위치와 실행

- 브랜치: `codex/agent-workspace`
- worktree: `/Users/jgy/workplace/tmp/cmux-worktrees/agent-workspace`
- 공통 기준: `169da41b5d27ae811bb5dfa41a99980be97b9949`; 공통 개발 실행/CLI optional fallback 수정 `dc12849f38` 및 `699e644174`를 후속 반영했다.
- 실행: `./scripts/dev-jmin-agents.sh --launch`
- CLI: `CMUX_TAG=jmin-agents ./scripts/cmux-debug-cli.sh <command>`
- 앱 설정: `~/.config/cmux-dev/jmin.agents/cmux.json`; 번들: `com.cmuxterm.app.debug.jmin.agents`.
- launcher는 이 번들의 Agent Chat UI override를 켜며, `agentChat.url/startCommand`가 모두 없을 때만 이 worktree의 Bun sidecar 실행 명령을 추가한다. 기존 사용자 설정은 보존한다. `agent-chat/`의 `bun install --frozen-lockfile` 필요(이 worktree에서는 실행함).
- 명령 팔레트의 **Claude Code Teams / Codex Teams**로 시작하면 실제 hook session binding을 기다린 뒤 같은 panel을 그룹으로 전환한다. 이미 실행 중인 로컬 Claude/Codex는 **Open terminal as chat**로 전환한다. 기존 terminal panel 안에서 표시를 전환하며 새 split을 만들지 않는다. 왼쪽 위 **터미널로 돌아가기**는 sidecar 로드 실패 때도 사용할 수 있다.

## 연결된 동작

- 메인 `Chat`와 composer는 항상 같은 SessionContext에 남는다. 멤버 선택은 별도 읽기 전용 상세만 바꾼다. 뒤늦은 이전 멤버 응답은 폐기한다.
- Claude 하위 기록은 루트 세션의 `subagents/agent-*.jsonl`와 실제 `sessionId/agentId`를 함께 검증한다. 루트 parser에서 숨기던 sidechain을 해당 하위 파일 안에서만 읽는다.
- Claude Teams는 `teams/*/config.json`의 `leadSessionId`가 루트와 정확히 같은 파일에서만 member를 연결한다. 실제 `sessionId`/subagent metadata가 있는 멤버만 대화를 연결하며, ID 없는 멤버는 이름과 unknown 상태를 표시한다.
- Codex는 실제 `spawn_agent` 결과의 `agent_id`를 관계 근거로 쓴다. hook 없는 child rollout도 자신의 `session_meta.source.subagent.thread_spawn.parent_thread_id`가 루트를 지목할 때만 허용한다. 단순 parent/fork metadata·cwd·PID로 관계를 만들지 않는다.
- Teams 그룹 실행은 `CMUX_AGENT_WORKSPACE=1`로 명시한다. Claude는 기본 `--teammate-mode in-process`를 사용하고 기존 split 유도 system prompt를 제외한다. 명시한 provider mode는 그대로 보존한다. Codex watcher는 실행 중인 app-server child를 추가 TUI/surface로 attach하지 않고 실제 `thread_spawn` parent·상태를 dev 설정 아래 `agent-workspace/codex/<surface>.json`으로 내보낸다. 웹은 root에서 이어진 graph만 연결하며 다른 root/fork·workspace 불일치는 제외한다. watcher 기록이 30초 이상 갱신되지 않으면 상태를 unknown으로 표시한다. provider 프로세스/승인 bridge 소유권은 기존 실행 경로에 남는다.
- restore 환경은 boolean group marker만 보존하고 임의 상태 저장 경로는 재생하지 않는다. native sidecar는 이 앱의 config root에서 metadata를 읽는다.
- 식별자가 없는 spawn 도구는 별도 **관찰된 실행** 항목이다. 도구가 반환되거나 부모 turn이 끝나도 하위 작업 완료라고 표시하지 않는다. 같은 workspace의 다른 세션은 **미지정**으로 표시한다.
- 권한 없는 capability는 비활성화한다. trace-only child에 terminal을 생성하지 않는다. 현재 지원 provider는 로컬 Claude/Codex다.
- `/api/agent-workspace`는 token prefix·Origin·현재 workspace registry·고정된 루트 ID를 확인한다. 브라우저는 파일 경로를 보낼 수 없고, member ID는 서버가 만든 map에서만 찾는다. child symlink 탈출도 거부한다.
- root와 같은 workspace의 live direct terminal은 그룹 아래 영역에서 기존 Ghostty renderer를 exclusive lease로 한 번만 표시한다. 원래 tab은 그룹 열기 버튼으로 renderer를 양보한다. panel/PTY/Bonsplit 소유권·UUID는 유지한다. 루트 container selection과 실제 member input target을 분리하며 explicit CLI panel ID는 바꾸지 않는다. 숨길 때 focus/visibility/portal generation을 갱신한다. 그룹 숨기기·member 선택·페이지 갱신은 agent 실행을 소유하지 않는다.
- `CmuxWebView`를 사용해 기존 copy/paste/undo/responder 경로를 재사용한다. Find 메뉴·팔레트는 현재 웹/터미널 responder에 따라 분기한다. hibernation resume 확인은 그룹 focus보다 먼저 수행한다. workspace 이동 시 그룹 표시를 해제하고 같은 terminal identity를 유지한다.
- 독립 검토에서 ended record의 surface ID가 남아 이전 멤버로 보이는 raw terminal이 유지되는 문제를 재현했다. terminal capability는 현재 live binding만 허용하며, 선택 멤버가 ended/missing이면 UI는 대화로 돌아간다. native는 service의 동기 변경 통지와 root/member session·provider·live index·PID fence로 이미 mount된 renderer를 해제한다. main composer의 mobile.chat 입력에도 같은 fence를 적용해 종료/교체된 세션의 살아 있는 PTY로 전송하지 않는다. 실제 React ended-state discriminator 통과, native registry 변경 회귀는 app test 실행 대상으로 추가했다.
- terminal detail 접기는 native lease를 해제하고 다시 펼치면 같은 session/surface를 재검증해 표시한다. 이전 host의 늦은 dismantle은 새 host의 callback을 지우지 못하도록 current owner를 확인한다. workspace/panel close·move·hibernate·group replacement도 lease를 해제한다.
- 선택·collapse·detail mode는 버전 1 데이터로 **이 앱의 UserDefaults**에 저장한다. 재실행 후 같은 루트에서 그룹을 다시 열면 복원한다. 없어졌던 멤버로의 selection은 유지하고 missing 상태를 보여준다. 자동 agent 재실행은 없다.
- 본문은 파일당 최근 4 MiB로 제한하고 잘린 기록임을 표시한다. child 탐색은 metadata 64 KiB 및 최대 100개로 제한하며, 캐시는 원본 크기 기준 합계 8 MiB로 제한한다.

## 검증

- `scripts/verify-local.py --swift-changed`: 17/17 selected checks 통과(2026-10-29). native compilation/launch는 별도 대상이다. source/test wiring과 Swift parse, localization·schema·feature-flag 검증을 포함한다.
- `agent-chat`: `tsc --noEmit`, `bun run build.ts` 통과.
- 전체 `bun run test`: 46 assertion scripts 및 20 bun:test files, 137 tests 통과. 정책 테스트가 새 CSS의 `cursor:pointer`를 잡아 `cursor:default`로 수정한 후 전체 재실행 통과.
- 새 projection suite: 실제 부모/자식 파일, identity/provider 불일치, symlink 탈출, 중복 spawn, background 종료 오판 방지, fork 비병합, Codex trace-only metadata, selection 복원, 20개 locale 검사. Claude Teams 정확한 lead/session 검증 및 Codex out-of-order descendant/foreign-root/fork/stale 검증도 포함한다.
- React 동작 테스트: 메인 composer mount/초안 유지, A→B 선택 후 늦은 A 응답 차단, trace-only terminal 비활성화, 실행/전송/중단 명령 미발생.
- 실제 임시 sidecar HTTP 테스트: token 없는 접근 거부, 다른 workspace·바뀐 루트 거부, member path injection 거부, 실제 transcript detail 반환. Origin 거부 assertion이 처음 200으로 실패했고 명시적 검사를 추가한 뒤 403으로 통과했다. 실제 provider 프로세스는 시작하지 않았다.
- IAB에서 실제 sidecar 페이지를 열어 메인 초안과 child 대화의 동시 표시 및 terminal 비활성화를 확인했다. 화면: `/tmp/cmux-jmin-agents-web-smoke.jpg` (합성 fixture, 실제 사용자 대화가 아님).
- Swift `CMUXAgentLaunch` package: Xcode toolchain + native build system, `AgentWorkspaceLaunchPolicyTests` 4개 통과(기본/그룹 mode, watcher 환경 전달, 원자적 metadata 저장, restore marker 보존/임의 경로 제외).
- `tests/test_cli_agent_workspace_teams.py`: feature CLI에 fake Claude와 Codex app-server를 연결해 in-process argv·실제 lineage export·surface.split 미발생을 검증하도록 작성했다. 실제 CLI 생성 후 실행해야 한다.
- `scripts/localize-changes --base 169da41...`: macOS 새 5개 키 9개 locale 완료, strict catalog 0 parity errors. web feature copy는 agent-chat의 20개 locale로 작성·검사했다.
- `cmuxTests/AgentWorkspacePresentationTests.swift`를 target에 연결했다: group Find가 숨긴 terminal search로 가지 않는지, 그룹 숨기기/이동 시 panel·surface identity 보존, URL의 루트/workspace 고정을 검사한다. **native app test target은 아직 컴파일·실행 전이다.** `AgentWorkspaceRendererLeaseTests`도 target에 연결했다(14 cases): member 전환/단일 소유권, original ID 타겟 유지, stale callback eligibility, root/member 이동·닫기·hibernation, lease 충돌 및 실제 registry에서 root/member 종료·교체·dead PID·서비스 종료 시 동기 lease 해제를 검증한다. `AgentWorkspaceInputBindingTests` 2 cases는 종료/교체된 root의 composer 입력이 surviving PTY에 전달되지 않고 not_found로 거절되는지 확인한다.

## 남은 범위와 native 검증

1. native lease는 같은 workspace의 live direct TerminalPanel에 적용한다. Canvas, remote-tmux mirror, cloud/device attachment, closing/hibernating, 다른 workspace 또는 다른 그룹이 이미 빌린 panel은 원래 panel focus로 fallback한다. 원격/기기용 renderer의 복제를 만들지 않는다.
2. Teams palette launcher의 자동 진입과 group-mode pane 방지는 구현했다. 임의 shell에서 직접 실행한 CLI는 수동 그룹 전환이 필요하다. 명시적으로 Claude `--teammate-mode tmux`를 지정하면 요청한 분할 모드를 유지한다. 이미 존재하는 pane 자체를 삭제하거나 숨기지는 않는다.
3. 앱 재시작 시 group UI는 자동 재표시하지 않고 같은 루트에 재진입하면 selection을 복원한다. 실행 상태는 live registry와 재검증한다.
4. tagged native 앱 빌드·실행, root terminal 입력/resize, web↔terminal copy/paste/Find, permission prompt, hibernation resume, 다른 workspace 이동, 앱 종료/복원 smoke가 남아 있다. root terminal PID 및 surface 수가 표시 전환 전후 그대로인지 실제 실행으로 확인해야 한다.
5. terminal 패널을 닫는 행위는 기존 explicit close 의미를 유지한다. **그룹 숨기기**와 **panel 닫기**를 구분한다.

native 앱 검증이 완료되기 전까지 PRD3 전체 완료로 표시하지 않는다. 현재 범위는 [SDD](../architecture/prd3-agent-workspace-sdd.md)에도 기록했다.

## 되돌리기

feature commit을 되돌리면 기존 terminal→browser split 진입으로 돌아간다. 개발 launcher는 전역 `/tmp/cmux-cli` 링크를 갱신하지 않는다. 선택 metadata는 dev 번들 UserDefaults의 `agentWorkspace.selection.v1.*`에만 남으며 무시 가능하다. launcher가 만든 dev 설정의 `agentChat.startCommand`와 해당 번들의 Agent Chat UI override는 필요 시 제거할 수 있다. 설치된 cmux의 설정·프로세스는 수정하지 않았다.

## Provider 근거

Claude의 in-process/Teams config 형태는 [공식 Agent Teams 문서](https://code.claude.com/docs/en/agent-teams)의 display mode·architecture 절과 기존 cmux CLI의 실제 launcher를 기준으로 연결했다. `--teammate-mode`는 실험적 플래그로 `claude --help`에는 표시되지 않는다. provider schema가 바뀌면 멤버를 추정하지 않고 capability를 비활성화한다.

## 실제 앱 호스트 검증 결과 (2026-10-29, 실측)

### 첫 성공 빌드
- `afeca10f75`로 태그 앱(`jmin-agents`) 빌드 **성공**(`CMUX_RELOAD_APP_EMIT_MODULE=1 ./scripts/dev-jmin-agents.sh --launch --no-global-cli-links`, 562초, `BUILD SUCCEEDED`, 컴파일 오류 0). `ping` = PONG. 이전 `TerminalPanelView.swift:102` 오류는 재발하지 않았다. 이후 테스트 전용 커밋(`7d9dbbf149`, `3621fe575a`, `678d05fdd8`)을 반영해 다시 빌드·실행했다.

### 앱 호스트 테스트 (runner `agents`, 실제 xcresult 기준)
| suite | 실행 | 통과 | 실패 |
|---|---|---|---|
| AgentWorkspacePresentationTests | 4 | 4 | 0 |
| AgentWorkspaceRendererLeaseTests | 11 (매개변수 사례 포함 시 14) | 11 | 0 (`7d9dbbf149` 이후) |
| AgentWorkspaceInputBindingTests | 1 (매개변수 `ended:` 2사례) | 1 | 0 |
| CmuxAgentChatConfigTests | 30 | 30 | 0 |
- 첫 실행에서 `switchingMembersPreservesSessionsAndRevokesOldHostEligibility`가 `debugPortalVisibleInUI == false`로 실패(11개 중 1개). 원인: 앱 호스트에서 `Workspace()` 단독은 등록된 TabManager가 없어 `portalRenderingEnabled`가 거짓. 테스트가 `TerminalPortalTestWorkspace`를 쓰도록 수정(`7d9dbbf149`), 같은 명령으로 red→green. 제품 코드 결함은 아니다.
- 호스트는 서명 없는 빌드(`CODE_SIGNING_ALLOWED=NO`)다. 아래 runner 수정 참고.
- 확인하지 못한 것: `MacSentryStartupPolicyTests/appHostUsesSchemeScopedUserConfigurationHome`(격리 확인 테스트)는 선택자에 넣었으나 xcresult 테스트 목록에 나타나지 않았다. 호스트 receipt 파일은 6개 생성됐다. 격리가 검증됐다고 주장하지 않는다.

### runner 수정 (검사 우회 없음, 사본: `.git/jmin-feature-coordination/handoff-20261029/prd3-run/runner.py`)
1. `ROOT`를 `/tmp/...` 표기로 유지(Xcode `TARGET_BUILD_DIR`이 비해석 경로라 `TEST_HOST`와 불일치 오류).
2. Xcode 27.1에서 `cmux-unit` 그래프가 앱 서명 때문에 `Cycle inside cmux`(Dock Tile plugin CodeSign ↔ Nucleo FFI 스크립트 단계)를 낸다. 변경 없는 `test-unit.sh build-for-testing`도 동일했고(스킴 `cmux` build는 아님), `PRODUCT_NAME` 재정의와 무관했다. `CODE_SIGNING_ALLOWED=NO`로 해결하고 서명 재정의는 제거. `PRODUCT_NAME` 재정의도 제거(기본 `cmux DEV`).
3. `cmuxCLITestSupport` 소스가 `BundledCLITestSupport`(`BundledCLILinkageTests.swift`)를 요구해 공통 소스에 추가.
4. 복제된 DerivedData의 `ModuleCache.noindex`는 원본 경로에 묶여 오류가 되므로 복제본에서만 삭제.
5. suite 하나가 실패해도 나머지를 실행하고 마지막에 실패 suite를 보고(원 실패는 xcresult에 보존).

### CLI 통합 테스트
`runner.py cli --profile agents --cli <jmin-agents CLI>` 결과 PASS. 처음에는 실패했고 원인은 테스트였다: (a) 앱이 만드는 per-surface claude shim root가 없어 실제 Teams 실행이 거부됨, (b) 관리 wrapper를 실제 provider로 넘겨야 함, (c) Codex watcher 플래그는 `--max-auto-depth`. `3621fe575a`에서 수정(red→green).

### 웹·정적
- agent-chat `bun run test`: 137 tests + 46 scripts 통과, `tsc --noEmit` 통과. 처음에 `agent-workspace-http.test.ts`가 실패: 이 머신의 `claude`가 cmux wrapper라 sidecar가 `hooks claude inject-settings`를 호출하고 over-broad assertion이 거부. rpc 요청만 검사하도록 수정(`678d05fdd8`).
- `scripts/verify-local.py --swift-changed`: 16/17 실행(swift-syntax는 선택된 Swift 파일 없음으로 SKIPPED), 실패 0. `Packages/macOS/CMUXAgentLaunch` `swift test --build-system native`: 871 tests 통과(전체 패키지).

### 네이티브 그룹 UI 검증 (2026-10-29 22:3x, 실측; 앱 `25bd09aa7e` 계열 재빌드)
실제 `jmin-agents` 앱과 cmux-cua(foreground 전달)로 fixture 세션(root/B/C, 서로 다른 PID·PTY·surface, 한 workspace)을 검증했다. 설정은 PLAN대로 QA sidecar 명령으로 덮어썼다가 백업과 바이트 동일하게 복원했다.

**처음 실제 앱으로 열자 제품 결함 2개가 나왔다(웹/호스트 테스트로는 보이지 않았다).**
1. `mobile.chat.sessions`가 control socket에 없어 `method_not_found` → 그룹 API가 `503 registry_unavailable`. 수정: 패키지 coordinator seam·실행 정책·capabilities·앱 witness에 추가(`c3c4e17ef0` 직전 커밋, 패키지 회귀 테스트 red→green, `CmuxControlSocket` 632 tests 통과).
2. 실제 응답은 snake_case(`session_id`, `agent_kind`, `terminal_id`)이고 state가 `{state: ...}`인데 sidecar는 임의 camelCase를 기대해 `409 binding_missing`. 수정: `normalizeSessionBindings`와 HTTP 테스트 fixture를 실제 형태로 교체(red→green), 웹 137 tests + 46 scripts + `tsc` 통과.

**관찰한 것(통과)**
- "터미널을 채팅으로 열기" → 메인 에이전트 대화 + composer + 멤버 칩(traceonly, QA Member B, QA Member C). API도 root, trace-only child, B, C를 반환.
- 팀원 B/C 선택 시 읽기 전용 대화가 나오고 메인 composer는 root 소유 유지("메인 대화에서 답하세요").
- trace-only: `원본 터미널` 비활성(회색), 대화/도구 실행만 가능.
- B의 `원본 터미널`을 그룹 안에 표시: 같은 PID 83240/PTY ttys019, 새 provider 생성 없음. 명시적 ID로 보낸 마커가 각각 root/b/c에만 도달(`verify-marker` PASS 3/3). 그룹에 보이는 B 렌더러에 GUI로 입력한 `GUI-B-MARK-7731`은 b에만, main composer로 입력한 `GUI-ROOT-COMPOSER-5512`는 root에만 도달. 전환 전후 PID/TTY(83028/83240/83336, ttys018/019/020) 동일.
- 종료: 그룹에 보이는 B와 C에 `/qa end`(정확한 대상 지정) → 즉시 터미널이 내려가고 대화로 복귀, 칩이 `종료됨`, `원본 터미널` 비활성. 종료된 C 자리에 입력해도 B/C 셸 어디에도 마커 없음(read-screen 확인).
- 같은 PTY 재바인딩: B 표면에서 `--replacement`(새 PID 90456, 같은 surface) → 이전 B는 `ended`·terminal false, 새 세션은 별도 `미지정` 칩. 이전 B를 선택해도 `원본 터미널` 비활성. root도 종료 후 같은 PTY에서 replacement 시작(PID 90859): composer의 미전송 초안을 전송했지만 replacement 입력 로그와 셸 화면에 도달하지 않았다.
- composer에 입력만 하고 Enter를 누르지 않은 텍스트는 어떤 PTY에도 도달하지 않았다.

**관찰했으나 결론을 내리지 않은 것(결정 필요)**
- 터미널이 표시되지 않은 상태에서 상세 영역(입력창이 아닌 곳)을 클릭하고 입력한 `POST-END-C-LEAK-9921`이 **root의 숨은 PTY로 전달**됐다(1회 관찰, 종료된 C/B에는 전달 안 됨). 숨은 root 터미널이 first responder로 남는 것으로 보이며 의도 여부 확인이 필요하다.
- root 종료 뒤 composer 전송 시 UI에 말풍선("Processed 1 event")이 남지만 실제 전달은 없었다. 오류 배너는 관찰하지 못했다.

**실행하지 않은 것**: resize/zoom, Find·copy/paste, 다른 split/배경 탭 상태, workspace 전환, hibernation, 권한 프롬프트, 앱 종료/복원, 실제 Claude Teams/Codex 프로세스. fixture 질의 외의 Codex 경로는 CLI 통합 테스트만 있다.
정리: 모든 fixture 프로세스 종료, QA workspace 2개 닫음(이전 실행의 복원본 포함), `cmux.json` 복원, QA sidecar 종료. 앱(`jmin-agents`, PID 82097)은 실행 중이며 `/tmp/cmux-jmin-agents-native-qa-xr3u18w2`에 증거 파일을 남겼다. 빌드 lock 해제.
