---
title: ADR-0002 창 밖 드롭은 같은 프로세스의 live panel 이동으로 처리
type: decision
date: 2026-10-29
author: jmin8008 (설계 초안 작성 지원 Codex)
status: proposed
issue:
tags: [decision, prd2, window-transfer, jmin-fork]
---
# ADR-0002 실행 상태를 보존하는 새 창 분리

> 한 줄 요약: 개별 panel과 workspace 전체를 모두 기존 세션을 유지한 채 같은 프로세스의 새 NSWindow로 옮기는 구조를 제안한다. 대상: 사람(의사결정).

## 문제 (Why now)

사용자는 cmux 내부 패널을 밖으로 끌어 독립 창처럼 배치하고 싶다. 터미널과 브라우저를 재생성하면 실행 작업, 입력 중인 내용, 페이지 상태를 잃을 수 있어 ‘창 분리’의 의미를 live 이동으로 정할 필요가 있다.

규모는 개인용 포크 기능 실험이다. 기존 `moveSurface`, `moveWorkspaceToNewWindow`, pane transfer registry가 있으므로 새로운 세션 전송 프로토콜을 만들 이유는 없다.

## 제약·비목표

- 실행 환경은 [SDD §4](../architecture/prd2-drag-out-window-sdd.md)의 단일 로컬 앱 프로세스다.
- 2026-10-29 사용자 결정으로 workspace 전체 분리를 1차에 포함하고, 마지막 패널 이동 뒤에는 기존 빈 workspace 정책을 유지한다. 개별 패널만 구현해서 이 PRD 전체를 완료로 표시하지 않는다.
- terminal process/session과 browser webview를 유지한다. 창 분리는 실행 중단·재개와 다르다.
- 임의 외부 앱 창·다른 cmux 프로세스·다른 머신의 OS 창을 가져오는 기능은 제외한다.
- `NSDragOperation.none`은 외부 drop의 충분한 근거가 아니다. 취소와 실제 release를 구분할 수 없는 경우 이동하지 않는다.

## 선택지 (최소 2개)

| 안 | 요지 | 복잡도 | 장점 | 단점·위험 |
|---|---|---|---|---|
| A (최소안) | 새 창을 만들고 명령/URL을 다시 실행 | 낮음 | 창 생성 연결이 단순 | 프로세스·폼·히스토리 보존 실패 |
| B (제안) | 기존 transfer 경로로 live panel 이동 | 중간 | 세션 유지, 기존 owner 모델 재사용 | 원자적 소유권 변경과 실패 보상 필요 |
| C | 새 cmux 프로세스를 띄우고 IPC로 세션 이전 | 높음 | 프로세스 분리 | PTY/WebKit 이전, 인증·복구 비용이 과도 |

## 결정

**구조 제안: B. 상태는 proposed다.** 개별 패널과 workspace 전체 포함, 기존 빈 workspace 정책 유지는 사용자 채택 사항이며, 아래 구현 구조 전체가 채택되거나 검증됐다는 뜻은 아니다.

기존 drag registry와 move 서비스를 사용하고 외부 release를 판정하는 작은 coordinator를 추가한다. source를 유지한 채 target을 준비하며 attach 성공 후에만 source 빈 상태와 target bootstrap을 정리한다. 내부 drop 수락이 외부 분리보다 우선한다.

payload에 panel/workspace scope를 구분한다. panel 이동은 기존 surface transfer, workspace 전체 이동은 기존 workspace transfer를 사용한다. workspace를 여러 panel의 순차 분리로 흉내 내지 않고 분할·탭·선택·세션을 한 단위로 보존한다.

단순안 A는 상태 보존이라는 창 분리의 실질적 요구를 만족하지 않는다. B의 추가 복잡도는 기존 이동 코드 재사용으로 제한한다. 새로운 프로세스·원격 전송·세션 복제는 요구가 생길 때 별도로 검토한다.

## 결과·영향

- 탭 헤더, sidebar, 메뉴의 관련 이동 진입점은 기존 transfer 경로로 모인다. drag 종료 처리만 별도 변형하여 소유권을 중복 관리하지 않는다.
- PRD1은 이동 후에도 panel identity로 목적지를 찾는다. PRD3는 UI를 닫거나 옮기는 행동과 에이전트 종료를 구분해야 한다.
- 기능 브랜치는 기존 터미널·브라우저로 독립 검증한다. 다른 PRD 구현을 기반 브랜치로 삼지 않는다.
- 구현 순서: 종료 판정/중복 방지 → live 이동 연결 → 실패 보상 → 패널·모니터별 GUI 검증. 구체 태스크 파일과 커밋은 아직 작성하지 않았다.

## 시기·적용 한계·출처

- 요구·조사·작성일: 2026-10-29. 적용 시기: 미정.
- 기준: HEAD `ef3d1307e116d1c0ba3c6f5ea124a6d28f6c01fe`와 관찰 당시 작업 트리. main 작업의 변경을 이 설계의 완료 증거로 사용하지 않는다.
- 참조: [AppDelegate](../../../Sources/AppDelegate.swift), [ExternalTabDrop](../../../Sources/Workspace+ExternalTabDrop.swift), [PaneTransferDropRouter](../../../Sources/PaneTransferDropRouter.swift), [sidebar drag lifecycle](../../../Sources/Sidebar/AppKitList/SidebarWorkspaceTableController.swift).
- 출처·라이선스: 저장소 소스를 설계 근거로 읽었다. [LICENSE](../../../LICENSE), [THIRD_PARTY_LICENSES](../../../THIRD_PARTY_LICENSES.md)의 기존 고지를 유지한다. 외부 구현 복사·새 라이브러리 도입은 없다. AppKit의 실제 취소/드롭 이벤트 동작은 구현 단계 실험이 필요하다.

## 호환성 영향·지원 종료

- 기존 내부 drag/drop, source 마지막 panel 정책, 세션 저장과 focus 경로가 영향 대상이다.
- 새 공개 socket API나 영속 데이터 형식 변경은 제안하지 않는다. 기존 저장 레이아웃을 사용한다.
- 지원 기간은 미정. 기존 기능 제거·지원 종료는 해당 없음.
- 구현 담당은 기능 브랜치 작업자이며 [SDD §6](../architecture/prd2-drag-out-window-sdd.md)의 GUI·실패 주입 결과를 완료 근거로 남긴다.

## 되돌리는 조건

- Escape로 취소한 drag에서 새 창이 생기거나 terminal/session identity가 바뀌면 외부 분리 기능을 비활성화한다.
- 복구 실행자는 기능 구현자, 설계 재검토자는 포크 소유자다.
- gesture 비활성화는 이후의 이동만 막는다. 이미 이동한 패널은 기존 창 이동 명령으로 옮길 수 있어야 한다. 실패 보상 없이 source를 파괴하는 구현은 채택하지 않는다.
- 불가역 비용은 실행 중 세션의 소실이므로 그 경로를 허용하지 않는 것이 채택 조건이다. 앱 충돌 자체의 복구 보장은 별도 세션 복원 기능의 범위다.
