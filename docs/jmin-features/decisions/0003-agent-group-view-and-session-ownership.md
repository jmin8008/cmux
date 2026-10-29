---
title: ADR-0003 에이전트 그룹 화면과 실행 세션의 수명을 분리
type: decision
date: 2026-10-29
author: jmin8008 (설계 초안 작성 지원 Codex)
status: accepted
issue:
tags: [decision, prd3, agent-workspace, jmin-fork]
---
# ADR-0003 한 그룹 화면과 독립 실행 세션

> 한 줄 요약: 메인 대화를 유지하며 같은 surface에서 하위 작업의 대화·실행 기록·원본 터미널을 펼쳐보고 실행 세션은 독립적으로 유지하는 방향을 채택한다. 대상: 사람(의사결정).

## 문제 (Why now)

서브에이전트나 팀원이 늘어날 때마다 pane을 추가하면 한 작업의 진행을 따라가기 어렵다. 사용자는 정돈된 웹 대화와 실제 터미널 실행을 함께 보면서 한 workspace의 화면 수를 관리하고 싶다.

규모는 개인 개발용 cmux 포크이다. 기존 agent-chat, session registry, child bookkeeping이 있으므로 새로운 에이전트 실행 시스템보다 표현과 소유권 연결을 설계하는 것이 우선이다.

## 제약·비목표

- ‘하나의 surface’는 메인 대화와 하위 작업 상세를 포함하는 최상위 진입점 하나로 확정했다. 실제 terminal/session 여러 개는 별도 identity와 수명을 가진다.
- 원본 terminal이 없는 child는 기록만 표시한다. 관찰 가능한 이벤트와 존재하지 않는 내부 대화를 구분한다.
- Brain 웹의 정확한 UX·구현은 미확인이다. 최종 레이아웃의 기준으로 확정하지 않는다.
- 실행 환경은 [SDD §4](../architecture/prd3-agent-workspace-sdd.md)의 로컬 앱·기존 sidecar/CLI이다. 새 orchestration engine·LLM 서비스·클라우드 운영은 비목표다.

## 선택지 (최소 2개)

| 안 | 요지 | 복잡도 | 장점 | 단점·위험 |
|---|---|---|---|---|
| A (최소안) | 기존 pane를 유지하고 agent sidebar만 추가 | 낮음 | 현재 구조 재사용 | 자동 pane 증가와 대화 정돈 요구가 남음 |
| B (채택 방향) | 메인 대화 + 펼치는 하위 작업 detail + 원본 terminal, 실행 소유자는 유지 | 중간~높음 | 한 진입점, 원본 실행 확인, 세션 연속성 | group host·layout projection·provider capability 연결 필요 |
| C | 자체 웹 agent runtime으로 전부 실행 | 높음 | 하나의 UI 계약을 만들기 쉬움 | 기존 CLI 동작·권한·재개를 다시 구현, 요구 범위 초과 |

## 결정

**채택: B의 사용자 흐름과 세션 소유권 분리 방향.** 2026-10-29 ‘메인 대화 + 내부 작업 목록 + 같은 surface에 펼치는 실제 기록/원본 terminal’ 시나리오를 설명한 뒤 사용자가 동의했다. accepted는 설계 방향 채택이며 native host의 실현 가능성, provider 지원, 구현·검증 완료를 뜻하지 않는다.

- 웹 UI는 대화/목록을 표시하고 native host는 선택한 원본 terminal을 보여준다. terminal의 실행 수명을 웹 컴포넌트 mount/unmount에 결합하지 않는다.
- 같은 작업의 child/team 항목은 그룹 안에서 증가한다. 새 최상위 pane는 사용자가 명시적으로 꺼낼 때 만든다. 원래 작업 생성과 보기 생성은 다른 행동이다.
- registry를 읽는 projection을 만들고 parent-child/team/fork 관계의 근거를 기록한다. 동일 cwd나 비슷한 이름으로 부모를 추정해 확정하지 않는다.
- provider별 capability가 있는 기능만 UI에 활성화한다. terminal 없는 child의 가짜 terminal, 제어 경로 없는 항목의 입력/중단 버튼은 만들지 않는다.
- 구조화된 대화와 원본 terminal을 한 세션에 대응시키며 새 agent를 추가 실행해 동일한 것처럼 보이지 않는다.
- 메인 대화를 유지한 채 선택한 하위 작업 하나의 상세를 같은 surface 안에서 펼친다. 멤버 선택으로 메인 본문 전체를 대체하는 안은 기본 동작으로 채택하지 않는다. 아래/옆 배치와 반응형 처리는 세부 디자인에서 정한다.
- 하위 멤버에게 새 메시지를 보내는 UI는 원래 ‘보인다’는 요구와 분리한다. 1차 필수 범위로 자동 확대하지 않고 기존 원본 terminal 상호작용을 유지한다.

A는 원본을 쉽게 볼 수 있지만 사용자의 화면 수 관리 요구를 충분히 풀지 못한다. B의 복잡도는 필요하나 native group host의 실현 가능성을 먼저 확인해야 한다. 구현 비용이나 수명 보존 문제가 크면 이 ADR을 다시 검토하며 임의로 A를 완료품으로 바꾸지 않는다.

## 결과·영향

- native panel/layout, agent-chat UI, session registry projection에 변화가 생긴다. 실제 agent loop는 기존 provider에 남는다.
- child 기록의 존재와 독립 session binding은 다르다. [현재 ChildRuns](../../../Sources/Mobile/AgentChat/AgentChatSessionRegistry+ChildRuns.swift)의 FIFO 종료 fallback을 확정적인 작업 성공으로 표현하지 않는다.
- 그룹 view 닫기·선택 변경·renderer restart가 실행 종료를 뜻하지 않도록 소유권을 분리한다. 원래 workspace 종료의 실제 process 정책은 유지한다.
- PRD1은 group UI ID 대신 실제 입력 가능한 terminal/session을 대상으로 한다. PRD2는 그룹과 꺼낸 panel의 한 owner 원칙을 지킨다. PRD4와 의존성이 없다.
- 순서 제안: native host spike → relationship/capability model → 그룹 UI → 입력/중단 → 복원. 태스크·코드·실제 에이전트 실행은 이번 요청에 포함하지 않는다.

## 시기·적용 한계·출처

- 작성·조사·채택일: 2026-10-29. 적용 목표 시기: 미정. 채택 근거는 PRD3의 구체적인 작업 장면과 화면 설명 뒤의 사용자 동의다.
- 기준 HEAD `ef3d1307e116d1c0ba3c6f5ea124a6d28f6c01fe`와 관찰 당시 작업 트리. provider의 실제 설치 버전과 protocol capability는 구현 시 기록해야 한다.
- 근거: [agent-chat](../../../agent-chat/README.md), [Workspace+AgentChat](../../../Sources/Workspace+AgentChat.swift), [SessionRegistry](../../../Sources/Mobile/AgentChat/AgentChatSessionRegistry.swift), [ChildRuns](../../../Sources/Mobile/AgentChat/AgentChatSessionRegistry+ChildRuns.swift), [types](../../../agent-chat/types.ts).
- [subagents-panel-plan](../../../docs/subagents-panel-plan.md)은 일부 설명이 현재 코드보다 오래되어 역사적 참고만 한다. Brain 및 t3code의 외부 코드는 이번에 열거나 복사하지 않았다.
- 라이선스: 기존 저장소의 [LICENSE](../../../LICENSE)와 [제3자 고지](../../../THIRD_PARTY_LICENSES.md)를 유지한다. 신규 의존성·외부 코드 복사는 제안하지 않는다. agent CLI의 별도 이용 조건을 이 문서가 재허가하지 않는다.

## 호환성 영향·지원 종료

- 기존 pane 세션, transcript 읽기, 입력/중단, app restore가 영향 대상이다. 새 UI를 끈 상태에서도 기존 탐색을 지원한다.
- 저장 group metadata는 optional/versioned 추가를 제안한다. 기존 세션 ID와 transcript format은 바꾸지 않는다. 새 metadata를 읽지 못하는 버전의 fallback을 검증한다.
- 기존 기능 지원 종료는 해당 없음. 출시·지원 기간은 미정이다.
- 구현 담당은 기능 브랜치 작업자. 완료 판단은 [SDD §6](../architecture/prd3-agent-workspace-sdd.md)의 동일 세션·정확한 대상·자동 pane 증가 방지 근거를 따른다.

## 되돌리는 조건

- UI 전환으로 agent가 재실행/종료되거나, 다른 세션에 입력되거나, 근거 없는 관계/상태를 확정 표시하면 그룹 조작 기능을 비활성화한다.
- capability 또는 native mount 한계로 원본 terminal을 일관되게 보여줄 수 없으면 B의 구조를 재검토한다. 대화 UI만 만든 상태를 전체 요구 완료로 보지 않는다.
- 결정 재검토 담당: 포크 소유자. 복구 실행 담당: 기능 구현자.
- 비용: 그룹 metadata를 무시하고 기존 live panel 탐색으로 되돌리는 경로가 필요하다. renderer를 닫아도 agent가 종료되지 않아야 한다. 이미 agent에 전달한 명령·외부 작업은 UI rollback으로 취소되지 않는다.
