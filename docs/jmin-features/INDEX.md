# INDEX — cmux 문서

> 생성물. 손으로 고치지 않는다 → `docs-index.py` (또는 `/bnx-dev-plan-change`). 갱신 2026-10-31. 규약: `bnx-dev-contract-guide`.

## 📌 핸드오프 (최근 3)
- [핸드오프 — 통합 앱(jmin-all)과 상류 PR 상태, 사내 대시보드 백본 전환 (2026-10-31)](implementation/2026-10-31-dashboard-backbone-handoff.md) — PRD1·2·4를 합친 `codex/integration`이 `jmin-all` 앱으로 빌드·실행 중이고, PRD2는 상류 PR 2건(bonsplit#294 → cmux#28191)으로 나가 있다. PRD1 드래그 선택이 블록 전체로 전달되는 결함과 CLA 서명이 남았고, 다음 작업은 이 브랜치를 백본으로 한 사내 대시보드다. 대상: 다음 세션(실행). · 2026-10-31 · active
- [핸드오프 — cmux 포크 개발과 남은 네이티브 검증 (2026-10-29)](implementation/2026-10-29-development-handoff.md) — 개발 환경·격리·V 로고와 4개 기능 코드를 준비했고, 설정 경고를 해결했다. 앱 바로가기 실행 오류와 창 분리·에이전트 화면의 수정 후 네이티브 검증이 남았다. 대상: 다음 작업자(실행). · 2026-10-29 · active

## 📋 PRD
- (없음)

## ⚖️ 결정
- [ADR-0001 화면 선택 맥락을 명시적인 터미널 대상으로 전달](decisions/0001-browser-context-handoff.md) — 클릭·드래그한 맥락을 대화하던 에이전트에 대괄호 텍스트로 삽입하고 사용자가 요청을 덧붙여 제출하는 흐름을 채택한다. 대상: 사람(의사결정). · 2026-10-29 · accepted
- [ADR-0002 창 밖 드롭은 같은 프로세스의 live panel 이동으로 처리](decisions/0002-live-panel-window-transfer.md) — 개별 panel과 workspace 전체를 모두 기존 세션을 유지한 채 같은 프로세스의 새 NSWindow로 옮기는 구조를 제안한다. 대상: 사람(의사결정). · 2026-10-29 · proposed
- [ADR-0003 에이전트 그룹 화면과 실행 세션의 수명을 분리](decisions/0003-agent-group-view-and-session-ownership.md) — 메인 대화를 유지하며 같은 surface에서 하위 작업의 대화·실행 기록·원본 터미널을 펼쳐보고 실행 세션은 독립적으로 유지하는 방향을 채택한다. 대상: 사람(의사결정). · 2026-10-29 · accepted
- [ADR-0004 바로가기는 사용자 설정의 typed 목록과 단일 resolver로 구현](decisions/0004-local-quick-launch-registry.md) — 앱과 웹을 구분한 바로가기 목록을 기존 사용자 설정에 저장하고 하나의 resolver로 열기·기존 화면 선택을 처리하는 방식을 제안한다. 대상: 사람(의사결정). · 2026-10-29 · proposed

## 🗂 계획
- (없음)

## 🩺 트러블슈팅 — 증상 → 문서
- (없음)

## 📘 런북
- (없음)

## 📚 문서
### architecture
- [PRD1 화면 선택 맥락을 터미널로 전달하는 설계](architecture/prd1-browser-context-sdd.md) — 내부 웹의 클릭과 텍스트 드래그를 자동 구분해 출처·위치·내용을 이미지 없이 대괄호 텍스트로 전달한다. 대상: 사람(설계 검토). · 2026-10-29 · draft
- [PRD2 패널을 창 밖으로 끌어 새 창으로 분리하는 설계](architecture/prd2-drag-out-window-sdd.md) — 개별 패널과 workspace 전체를 모두 창 밖 드롭으로 분리하고, 기존 레이아웃·실행 세션·빈 workspace 정책을 유지한다. 대상: 사람(설계 검토). · 2026-10-29 · draft
- [PRD3 한 작업 화면에서 에이전트 대화와 원본 터미널을 관리하는 설계](architecture/prd3-agent-workspace-sdd.md) — 부모·팀원·서브에이전트를 한 작업 화면에 묶고 대화·도구 실행·원본 터미널을 선택해 보되 실제 실행 세션은 독립적으로 유지한다. 대상: 사람(설계 검토). · 2026-10-29 · draft
- [PRD4 알림과 추가 버튼 사이의 앱·웹 바로가기 설계](architecture/prd4-quick-launch-sdd.md) — 알림 종과 추가 버튼 사이에 바로가기 목록을 열고 앱·웹·localhost 주소를 등록해 재사용한다. 대상: 사람(설계 검토). · 2026-10-29 · draft

## 🏷 태그
- `agent-workspace` (2): [PRD3 한 작업 화면에서 에이전트 대화와 ](architecture/prd3-agent-workspace-sdd.md) · [ADR-0003 에이전트 그룹 화면과 실행 ](decisions/0003-agent-group-view-and-session-ownership.md)
- `architecture` (4): [PRD1 화면 선택 맥락을 터미널로 전달하는](architecture/prd1-browser-context-sdd.md) · [PRD2 패널을 창 밖으로 끌어 새 창으로 ](architecture/prd2-drag-out-window-sdd.md) · [PRD3 한 작업 화면에서 에이전트 대화와 ](architecture/prd3-agent-workspace-sdd.md) · [PRD4 알림과 추가 버튼 사이의 앱·웹 바](architecture/prd4-quick-launch-sdd.md)
- `browser-context` (2): [PRD1 화면 선택 맥락을 터미널로 전달하는](architecture/prd1-browser-context-sdd.md) · [ADR-0001 화면 선택 맥락을 명시적인 ](decisions/0001-browser-context-handoff.md)
- `dashboard-backbone` (1): [핸드오프 — 통합 앱(jmin-all)과 상](implementation/2026-10-31-dashboard-backbone-handoff.md)
- `decision` (4): [ADR-0001 화면 선택 맥락을 명시적인 ](decisions/0001-browser-context-handoff.md) · [ADR-0002 창 밖 드롭은 같은 프로세스](decisions/0002-live-panel-window-transfer.md) · [ADR-0003 에이전트 그룹 화면과 실행 ](decisions/0003-agent-group-view-and-session-ownership.md) · [ADR-0004 바로가기는 사용자 설정의 t](decisions/0004-local-quick-launch-registry.md)
- `handoff` (2): [핸드오프 — 통합 앱(jmin-all)과 상](implementation/2026-10-31-dashboard-backbone-handoff.md) · [핸드오프 — cmux 포크 개발과 남은 네이](implementation/2026-10-29-development-handoff.md)
- `integration` (1): [핸드오프 — 통합 앱(jmin-all)과 상](implementation/2026-10-31-dashboard-backbone-handoff.md)
- `jmin-fork` (10): [핸드오프 — 통합 앱(jmin-all)과 상](implementation/2026-10-31-dashboard-backbone-handoff.md) · [PRD1 화면 선택 맥락을 터미널로 전달하는](architecture/prd1-browser-context-sdd.md) · [PRD2 패널을 창 밖으로 끌어 새 창으로 ](architecture/prd2-drag-out-window-sdd.md) · [PRD3 한 작업 화면에서 에이전트 대화와 ](architecture/prd3-agent-workspace-sdd.md) · [PRD4 알림과 추가 버튼 사이의 앱·웹 바](architecture/prd4-quick-launch-sdd.md) · [ADR-0001 화면 선택 맥락을 명시적인 ](decisions/0001-browser-context-handoff.md)
- `native-validation` (1): [핸드오프 — cmux 포크 개발과 남은 네이](implementation/2026-10-29-development-handoff.md)
- `prd1` (2): [PRD1 화면 선택 맥락을 터미널로 전달하는](architecture/prd1-browser-context-sdd.md) · [ADR-0001 화면 선택 맥락을 명시적인 ](decisions/0001-browser-context-handoff.md)
- `prd2` (2): [PRD2 패널을 창 밖으로 끌어 새 창으로 ](architecture/prd2-drag-out-window-sdd.md) · [ADR-0002 창 밖 드롭은 같은 프로세스](decisions/0002-live-panel-window-transfer.md)
- `prd3` (2): [PRD3 한 작업 화면에서 에이전트 대화와 ](architecture/prd3-agent-workspace-sdd.md) · [ADR-0003 에이전트 그룹 화면과 실행 ](decisions/0003-agent-group-view-and-session-ownership.md)
- `prd4` (2): [PRD4 알림과 추가 버튼 사이의 앱·웹 바](architecture/prd4-quick-launch-sdd.md) · [ADR-0004 바로가기는 사용자 설정의 t](decisions/0004-local-quick-launch-registry.md)
- `quick-launch` (2): [PRD4 알림과 추가 버튼 사이의 앱·웹 바](architecture/prd4-quick-launch-sdd.md) · [ADR-0004 바로가기는 사용자 설정의 t](decisions/0004-local-quick-launch-registry.md)
- `upstream-pr` (1): [핸드오프 — 통합 앱(jmin-all)과 상](implementation/2026-10-31-dashboard-backbone-handoff.md)
- `window-transfer` (2): [PRD2 패널을 창 밖으로 끌어 새 창으로 ](architecture/prd2-drag-out-window-sdd.md) · [ADR-0002 창 밖 드롭은 같은 프로세스](decisions/0002-live-panel-window-transfer.md)

<!-- index:manual:start -->
## 📌 자주 쓰는 사실 (이 구역만 손으로 편집)

이 묶음은 2026-10-29 요청한 SDD 4편과 ADR 4편이다. PRD1~4는 대화에서 붙인 기능 번호이며 별도 PRD 파일은 아직 없다. SDD는 세부 설계·검증이 남아 `draft`다. ADR-0001·0003은 설명 후 동의한 동작·설계 방향을 `accepted`로 기록했고, ADR-0002·0004는 제품 요구를 채택한 상태에서 세부 구조는 `proposed`로 남아 있다. 사용자 요구, AI 설계 제안, 코드에서 확인한 사실, 미검증을 구분하며 accepted를 구현 완료로 사용하지 않는다. ADR-0001~0004는 이 문서 묶음의 결정 번호다.

### 2026-10-29 후속 사용자 결정

- PRD1: 내부 브라우저·localhost·HTML, 클릭/텍스트 drag 자동 구분, 실제 대괄호 텍스트를 채택했다. 별도 선택 모드 UI·이미지·영역 선택은 1차에서 제외한다. 설명 후 동의에 따라 같은 workspace에서 방금 대화하던 agent 터미널로 자동 연결하고 삽입만 수행하며, 사용자가 요청을 덧붙여 Enter로 제출하는 흐름도 확정했다.
- PRD2: 개별 panel과 workspace 전체 분리를 모두 1차에 포함한다. 마지막 panel 이동 뒤에는 기존 빈 workspace 정책을 유지한다.
- PRD3: 구체화한 사용 장면에 동의했다. 메인 대화를 유지하며 내부 작업 목록에서 하위 에이전트를 고르고, 같은 surface에 실제 대화·실행 기록·원본 terminal을 펼친다. 자동 최상위 창 증가는 없고 직접 꺼낸 항목만 별도 panel이 되며 보기 변경은 실행 세션을 유지한다.
- PRD4: 클릭 목록 먼저, 앱 전체 공통, 현재 workspace의 기존 화면 재사용을 채택했다.
- 채택한 제품 동작은 미결로 되돌리지 않는다. 세부 모델·API·UI 배치와 실제 지원 여부는 구현 단계에서 확인하며 기능 완료로 표시하지 않는다.

### 기능별 바로가기와 제안 브랜치

| 기능 | 설계 | 결정 | 독립 실험 브랜치 제안 |
|---|---|---|---|
| PRD1 화면 맥락 → 터미널 | [SDD](architecture/prd1-browser-context-sdd.md) | [ADR-0001](decisions/0001-browser-context-handoff.md) | `codex/browser-context` |
| PRD2 창 밖으로 끌어 분리 | [SDD](architecture/prd2-drag-out-window-sdd.md) | [ADR-0002](decisions/0002-live-panel-window-transfer.md) | `codex/drag-out-window` |
| PRD3 한 작업의 에이전트 대화 관리 | [SDD](architecture/prd3-agent-workspace-sdd.md) | [ADR-0003](decisions/0003-agent-group-view-and-session-ownership.md) | `codex/agent-workspace` |
| PRD4 앱·웹 바로가기 | [SDD](architecture/prd4-quick-launch-sdd.md) | [ADR-0004](decisions/0004-local-quick-launch-registry.md) | `codex/quick-launch` |

### 공통 개발·통합 조건

- 문서 작성 시 현재 브랜치는 `codex/jmin-dev-isolation`이며 다른 작업에서 구현 중인 변경이 있었다. 이 문서 작업은 checkout·commit·push·feature branch 생성을 수행하지 않았다.
- 기준 HEAD는 `ef3d1307e116d1c0ba3c6f5ea124a6d28f6c01fe`이며 작업 트리는 고정된 릴리스가 아니다. 개발 환경 격리 변경을 검증·확정한 뒤 실제 분기 기준 SHA를 기록한다.
- 제안한 통합 브랜치 이름은 `codex/dev`이다. 네 기능 브랜치는 같은 확정 기준에서 분기하고, 서로의 미완료 브랜치 위에서 시작하지 않는다. 통합 브랜치도 이 문서 작업에서 만들지 않았다.
- 동시에 수정할 때는 기능별 worktree를 사용한다. 문서 작성 때는 worktree를 만들지 않았다. 공통 `AppDelegate`·titlebar·설정 연결은 작게 유지하고 기능별 helper에 책임을 둔다.
- 현재 [개발 wrapper](../jmin-development.md)는 `jmin` 태그를 고정한다. worktree만 나눈다고 실행 앱·socket·설정까지 분리되지는 않는다. 여러 빌드를 동시에 실행하기 전 고유 tag/bundle/socket/config 분리를 준비한다. 그 전에는 해당 개발 인스턴스에서 한 빌드씩 검증한다.
- SDD §6의 기능별 동작을 검증한 기능만 통합한다. 구현 순서 제안은 PRD4 → PRD1 → PRD2 → PRD3이며, 우선순위 확정이나 다른 기능의 선행 의존성을 의미하지 않는다.
- PRD1은 실제 terminal identity, PRD2는 panel owner, PRD3은 실제 agent session identity를 유지한다. 화면용 group ID를 입력 대상 session ID로 대체하지 않는다. PRD4는 다른 세 기능 없이 실행 가능하다.

### 검증과 남은 선택

- 수행 범위: 기존 코드·문서 확인, 8개 문서의 형식·상대 링크·색인 검사. 앱 구현·빌드·GUI 동작·provider 실험은 하지 않았다.
- 문서에 표시한 UI 문구는 제안이며 제품 문자열을 추가하지 않았다. 실제 구현에서 native/web localization audit을 수행한다. 진행 중인 다른 코드 변경을 포함하는 광범위한 자동 localization 작업은 이 문서 작업에서 실행하지 않았다.
- PRD1: 대상 표시/변경과 모호한 후보 처리, 텍스트 상한·gesture 판정. PRD2: provider별 transfer 지원과 특수 drop 대상. PRD3: 상세의 아래/옆 배치, Brain과의 정확한 대응, provider capability·native group host. PRD4: 등록 폼·기본 열 위치·재사용 후보 선택의 세부사항. 상세는 각 SDD의 남은 설계·검증 항목에 있다.
<!-- index:manual:end -->
