---
title: 핸드오프 — 통합 앱(jmin-all)과 상류 PR 상태, 사내 대시보드 백본 전환 (2026-10-31)
type: handoff
date: 2026-10-31
author: jmin8008
status: active
issue:
tags: [handoff, jmin-fork, integration, upstream-pr, dashboard-backbone]
---
# 핸드오프 — 통합 앱(jmin-all)과 상류 PR 상태, 사내 대시보드 백본 전환

> 한 줄 요약: PRD1·2·4를 합친 `codex/integration`이 `jmin-all` 앱으로 빌드·실행 중이고, PRD2는 상류 PR 2건(bonsplit#294 → cmux#28191)으로 나가 있다. PRD1 드래그 선택이 블록 전체로 전달되는 결함과 CLA 서명이 남았고, 다음 작업은 이 브랜치를 백본으로 한 사내 대시보드다. 대상: 다음 세션(실행).
> 기록 시점: 2026-10-31. 이전 자료: [2026-10-29 핸드오프](2026-10-29-development-handoff.md)(기본 저장소 `codex/dev` 체크아웃에 미커밋 상태로 있음), [상태](STATUS.md), [색인](../INDEX.md).

## 0. 재개 시 가장 먼저 볼 상태

| 항목 | 현재 값 | 비고 |
|---|---|---|
| 통합 브랜치 | `codex/integration` `23244f7a51` | `codex/dev` + PRD1 + PRD2 + PRD4 merge. PRD3 제외(사용자 선택) |
| 실행 중 앱 | `cmux DEV jmin-all.app` PID 5022, ping PONG | 공유 DerivedData `cmux-jmin-build/Build/Products/Debug/` |
| 설정 경로 | `~/.config/cmux-dev/jmin.all/` | 다른 태그와 분리 |
| 빌드 체크아웃 | `cmux-worktrees/build` = `23244f7a51` detached | `build-lock.sh status` = free |
| 상류 PR | bonsplit#294 open, cmux#28191 draft | 아래 §3 |
| 미해결 결함 | PRD1 드래그 선택 → 블록 전체 전달(사용자 보고, 미재현) | 아래 §2 |

통합 상태에서 세 기능의 실제 동작은 사용자 수동 확인만 있고 네이티브 검증은 하지 않았다.

## 1. 저장소·브랜치·워크트리

원격: `origin` = jmin8008/cmux(포크), `upstream` = manaflow-ai/cmux. bonsplit은 jmin8008/bonsplit 포크(원격 이름 `fork`)와 manaflow-ai/bonsplit(`origin`).

| 브랜치 | 워크트리(`cmux-worktrees/`) | HEAD | 내용 |
|---|---|---|---|
| `codex/dev` | `build`(빌드 전용) / 기본 저장소 `cmux/` | `8ec0a0d03e` | 공통 기반: V 아이콘, 태그별 설정, 로컬 백엔드 |
| `codex/browser-context` | `browser-context` | `d099db6044` | PRD1 화면 맥락 |
| `codex/drag-out-window` | `drag-out-window` | `1e8e0f5def` | PRD2 창 분리, `.gitmodules`가 bonsplit 포크를 가리킴 |
| `codex/agent-workspace` | `agent-workspace` | `e555ec520d` | PRD3 에이전트 화면(통합 미포함) |
| `codex/quick-launch` | `quick-launch` | `9357981d39` | PRD4 바로가기 |
| `codex/integration` | `integration` | `23244f7a51` | 통합. 이 문서가 있는 브랜치 |
| `feat/drag-out-window` | `upstream-drag-out` | `31a31ab5ca` | 상류 PR용. upstream/main `460f198fea` 위에 PRD2 커밋 6개 + 서브모듈 핀 |
| bonsplit `feat/native-drag-completion` | `bonsplit-upstream` | `e95ddd6` | 상류 bonsplit PR용 |

모든 브랜치는 포크 origin에 push됐다. 워크트리는 전부 clean이다.

PRD3의 사용자 결정 2건은 아직 열려 있다: 비입력 영역 클릭 후 숨은 루트 터미널이 키 입력을 받는 문제, 거부된 컴포저 초안이 오류 없이 전송 말풍선으로 보이는 문제. 상세는 `codex/agent-workspace`의 `docs/jmin-features/implementation/agent-workspace-handoff.md`.

## 2. 미해결 결함 — PRD1 드래그 선택이 블록 전체로 전달됨

사용자 보고(2026-10-30, jmin-all): 내장 브라우저에서 텍스트를 드래그했는데 선택 구간 대신 요소 전체 텍스트가 터미널에 들어갔다. 재현·원인 확정 전이다.

읽은 범위: `Packages/macOS/CmuxBrowser/Sources/CmuxBrowser/Resources/BrowserContextSelectionRuntime.js`의 mouseup 분기. "4px 이상 이동 + WebKit 선택 텍스트 있음"이면 `kind: text`로 선택 텍스트만, 이동 없으면 `kind: element`로 `innerText` 전체, 이동했는데 선택이 비면 전송 없음. 이 파일은 통합 merge로 바뀌지 않았고(`git diff codex/browser-context codex/integration -- Packages/macOS/CmuxBrowser` 비어 있음), PRD2의 `SidebarWorkspaceDragSourceMonitor`는 사이드바 영역 안의 mousedown만 추적한다.

후보 원인 2개:

1. 드래그 중 mousemove가 웹뷰에 전달되지 않아 클릭으로 분류됨. 링크·이미지·`draggable` 요소에서 시작한 드래그는 WebKit이 DnD를 시도하고, 런타임이 `dragstart`를 막는다.
2. 선택은 됐지만 범위가 블록 전체로 확장됨(페이지의 `user-select: all` 또는 자체 선택 처리).

사용자에게 물은 것(답 대기): 붙은 블록의 `"selection"` 값이 `element`인지 `text`인지, 어떤 페이지의 어떤 요소였는지. `element`면 1번이고, 이동이 감지됐을 때 요소 전체 대신 Range에서 드래그 구간 텍스트를 뽑도록 고친다. 수정 절차: `codex/browser-context`에 실패 테스트(`tests/browser-context/runtime.test.cjs`) 커밋 → 수정 커밋 → `codex/integration`에 merge → `jmin-all` 재빌드.

관련 미확인: PRD1 네이티브 경계 중 포인터 입력이 막혀 못 본 3건(스크롤·줌 좌표, 이미지·32KB 거부, 캡처 중 대상 닫기)과 같은 버튼 2회 클릭에 붙여넣기 3개가 들어온 의심 1건. `browser-context-handoff.md`의 2026-10-30 절 참조.

## 3. 상류 PR 2건

| PR | 브랜치 | 상태 | 할 일 |
|---|---|---|---|
| manaflow-ai/bonsplit#294 | `feat/native-drag-completion` `e95ddd6` | open, 검사 없음 | 메인테이너 응답 대기 |
| manaflow-ai/cmux#28191 | `feat/drag-out-window` `31a31ab5ca` | draft, CLA Assistant 실패 | PR 댓글로 CLA 서명 |

- **CLA 서명**: cmux#28191에 다음 문장을 그대로 댓글로 단다. `I have read the CLA Document v2.2 and I hereby sign the CLA`. 이후 `recheck` 댓글로 봇을 다시 돌릴 수 있다. 사용자 본인 계정으로 해야 한다.
- **순서**: #294가 먼저 머지돼야 한다. 머지되면 `upstream-drag-out`의 마지막 커밋(서브모듈 핀 `31a31ab5ca`)을 상류 bonsplit 커밋으로 바꿔 force-push한다. 그 전까지 상류 CI는 서브모듈을 받지 못한다.
- cmux PR 본문에 적은 미실행 항목: 상류 베이스에서 앱 빌드와 `DragOutWindowTransferTests`, CmuxFoundation 테스트 타깃(Xcode 27.1에서 무관 파일 컴파일 실패). 리뷰어가 요구하면 태그 빌드 한 번으로 갱신한다.
- Proof 절이 비어 있다. 터미널이 살아서 새 창으로 옮겨지는 짧은 클립을 넣는다.
- 상류는 squash merge이고 하루 50커밋 이상 쌓인다. 오래 두면 rebase가 필요하다.

## 4. 빌드·실행 절차

```bash
source /Users/jgy/workplace/tmp/cmux-toolchains/env.sh      # Xcode 27.1, CMUX_DERIVED_DATA 설정
/Users/jgy/workplace/tmp/cmux-worktrees/build-lock.sh acquire <owner> 3600
cd /Users/jgy/workplace/tmp/cmux-worktrees/build
git switch --detach codex/integration && git submodule sync vendor/bonsplit && git submodule update --init vendor/bonsplit
CMUX_DEV_BACKEND_MODE=local CMUX_RELOAD_APP_EMIT_MODULE=1 ./scripts/reload.sh --tag jmin-all --launch --no-global-cli-links
CMUX_TAG=jmin-all ./scripts/cmux-debug-cli.sh ping             # PONG
/Users/jgy/workplace/tmp/cmux-worktrees/build-lock.sh release <owner>
```

- 통합 브랜치에는 태그 래퍼가 없어 `reload.sh --tag`를 직접 쓴다. `env.sh`를 안 하면 debug CLI가 태그별 DerivedData를 찾다 실패한다.
- 중간 산출물은 2026-10-30에 지웠다. 첫 빌드는 20~30분, 이후 증분 빌드는 짧다. `Build/Products`(4.7G)는 실행 중 앱 번들이라 남겼다.
- 금지 사항 유지: bare `xcodebuild`, 태그 없는 앱, `/tmp/cmux-cli`, 전역 CLI 링크 교체, 사용자 stable cmux(`/Applications/cmux.app`) 종료·교체.

## 5. 다음 작업 — 사내 대시보드 백본

사용자 방향(2026-10-31): `codex/integration`을 백본으로 사내 대시보드를 만든다. 요구사항은 아직 정리되지 않았다.

시작 전에 확정할 것:

- "대시보드"가 cmux 안의 화면(새 패널·워크스페이스 종류)인지, cmux가 띄우는 별도 웹 앱(PRD4 바로가기로 여는 localhost)인지, 둘 다인지.
- 데이터 출처: 사내 BioNexus 대시보드 MCP·API를 쓰는지, 로컬 에이전트 세션 상태(PRD3 registry projection)를 쓰는지.
- 브랜치 전략: `codex/integration`에서 `codex/dashboard-<short-id>`를 분기하고, 기능 브랜치 수정은 계속 각 기능 브랜치에서 한 뒤 integration에 merge해 올린다. integration에 직접 기능을 넣지 않는다.
- 태그: 대시보드 빌드는 `jmin-all`을 재사용하거나 새 태그를 쓴다. 다른 개발 앱 5개 번들은 Products에 남아 있지만 실행 중인 것은 jmin-all뿐이다.

권장 첫 단계: PRD(`docs/jmin-features/prd/`)와 화면 설계 문서를 먼저 만들고, 기존 ADR-0001~0004와 충돌하는 결정만 새 ADR로 남긴다.

## 6. 세션 기록 보관 위치

- 라우팅 요청·관찰: `/Users/jgy/workplace/tmp/.fluent/request-cmux-fork-remaining-impl.json`, `obs-cmux-prd1..4.json`, task-state 6차 개정. 이 문서의 요청은 이 워크트리의 `.fluent/request-cmux-dashboard-handoff.json`.
- PR 초안 원문: 세션 scratchpad `pr-drafts/`(세션 종료 시 사라질 수 있음). PR 본문은 GitHub에 있다.
- PRD1 2026-10-30 네이티브 증거: 세션 scratchpad `prd1/`, `/tmp/cmux-context-*`.
- 기본 저장소 `cmux/`(`codex/dev`)에 2026-10-29 핸드오프·INDEX·STATUS 수정이 미커밋으로 남아 있다. 버리지 말고 커밋하거나 이 브랜치로 옮긴다.
