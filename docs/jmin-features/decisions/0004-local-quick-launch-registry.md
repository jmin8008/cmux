---
title: ADR-0004 바로가기는 사용자 설정의 typed 목록과 단일 resolver로 구현
type: decision
date: 2026-10-29
author: jmin8008 (설계 초안 작성 지원 Codex)
status: proposed
issue:
tags: [decision, prd4, quick-launch, jmin-fork]
---
# ADR-0004 로컬 앱·웹 바로가기 저장과 실행

> 한 줄 요약: 앱과 웹을 구분한 바로가기 목록을 기존 사용자 설정에 저장하고 하나의 resolver로 열기·기존 화면 선택을 처리하는 방식을 제안한다. 대상: 사람(의사결정).

## 문제 (Why now)

사용자는 자주 쓰는 앱과 웹, 로컬 웹을 알림 종과 + 사이에서 바로 열고 싶다. 등록 방식은 아직 정하지 않았으며, 처음부터 shell launcher나 자동 서버 관리까지 포함하면 범위와 실패 조건이 크게 늘어난다.

규모는 개인 개발용 포크 기능이다. 기존 설정 저장소, browser 생성, native 앱 실행을 연결하는 작은 기능으로 시작할 수 있다.

## 제약·비목표

- 요구된 위치는 유지한다. 2026-10-29 클릭 목록·앱 전체 공통·현재 workspace의 기존 화면 재사용을 사용자가 확정했다. 단일 버튼/popover와 등록 폼의 세부 UI는 제안이다.
- [SDD §4](../architecture/prd4-quick-launch-sdd.md)의 로컬 환경과 bundle identity 기반 설정 위치를 따른다. 설치 앱 설정과 개발 앱 설정을 섞지 않는다.
- 1차는 클릭 가능한 목록이다. 개별 키보드 binding은 1차에서 제외하고 향후 필요할 때 기존 shortcut 체계로 추가한다.
- 개발 서버 실행·임의 shell command·계정 동기화·웹 상태 polling은 비목표다.

## 선택지 (최소 2개)

| 안 | 요지 | 복잡도 | 장점 | 단점·위험 |
|---|---|---|---|---|
| A (최소안) | 고정된 링크와 앱을 코드에 작성 | 낮음 | 빠른 실험 | 사용자 등록/수정 불가 |
| B (제안) | typed entries를 user config에 저장, 공통 resolver 사용 | 중간 | 등록·복원·설정 격리·검증 가능 | schema와 UI 편집 필요 |
| C | 범용 shell/프로젝트 action launcher로 구현 | 중간~높음 | 서버 시작까지 확장 가능 | 실행 권한·프로세스 수명·실패 관리가 추가됨 |
| D | 별도 bookmark DB와 동기화 서비스 | 높음 | 대규모 관리와 동기화 | 개인 목록 요구에 불필요한 운영 비용 |

## 결정

**구조 제안: B. 상태는 proposed이다.** 클릭 목록·앱 전체 공통·현재 workspace 재사용은 사용자 확정 사항이다. 세부 등록 UI/저장 schema/OS resolver 구조는 설계 제안으로 구분한다.

- 목록 마지막의 추가 동작으로 웹 URL 또는 설치 앱을 등록한다. 사용자 설정의 `quickLaunch` namespace에 versioned typed entries를 저장한다.
- 웹과 앱은 다른 target 타입으로 두며 문자열을 shell command로 실행하지 않는다.
- global user 목록을 사용하고 in-app 웹은 현재 workspace의 기존 화면을 재사용한다. 세부 제안은 entry binding을 먼저 조회한 뒤 같은 profile/정확한 대상 URL의 기존 panel을 찾는 것이다. 수동으로 연 페이지도 포함하며 다른 작업 공간의 페이지를 자동 이동하지 않는다.
- 앱 열기는 OS 앱 식별/활성화 경로를 사용한다. 외부 브라우저 탭 재사용은 보장하지 않는다.
- 같은 항목 반복 클릭은 한 open 요청으로 합친다. localhost 접속 실패는 브라우저 오류로 다루며 개발 서버를 자동 시작하지 않는다.

A는 ‘등록은 어떻게 할지’라는 요구의 해결책이 되지 못한다. B는 기존 store로 복잡도를 제한한다. C는 사용자가 실행 명령 등록을 명시적으로 요구할 때, D는 실제 동기화 필요가 생길 때 별도 검토한다.

## 결과·영향

- titlebar의 정상/minimal/fullscreen 표현, 설정 schema/store, browser/app launch resolver가 변경 대상이다.
- 클릭·메뉴·향후 단축키는 같은 resolver를 호출한다. 단축키 충돌을 피하려고 별도 global event hook을 추가하지 않는다.
- 설정 위치는 [CmuxConfigLocation](../../../Packages/macOS/CmuxSettings/Sources/CmuxSettings/Stores/CmuxConfigLocation.swift)에서 얻는다. 진행 중인 환경 격리 작업이 통합되기 전에는 이 경로의 안정성을 확인한다.
- 다른 PRD와 구현 의존성이 없다. 공유 titlebar 파일 수정은 작은 연결 부분으로 제한해 branch 통합 충돌을 줄인다.
- 구현 순서: model/store → resolver → 등록·목록 UI → 배치/복원/개발 환경 검증. 이번에는 문서만 작성하며 등록 데이터나 설정을 실제로 바꾸지 않는다.

## 시기·적용 한계·출처

- 작성·조사일: 2026-10-29. 요구 근거는 같은 날짜 PRD4 대화. 적용 목표 시기: 미정.
- 기준 HEAD `ef3d1307e116d1c0ba3c6f5ea124a6d28f6c01fe`와 관찰 당시 작업 트리. `CmuxConfigLocation`과 개발 wrapper는 다른 작업에서 수정 중이었다.
- 근거: [ContentView](../../../Sources/ContentView.swift), [MinimalModeSidebarControls](../../../Sources/Update/MinimalModeSidebarControls.swift), [JSONConfigStore](../../../Packages/macOS/CmuxSettings/Sources/CmuxSettings/Stores/JSONConfigStore.swift), [개발 안내](../../jmin-development.md).
- 출처·라이선스: 저장소 구현을 참조했으며 외부 코드는 복사하지 않았다. [LICENSE](../../../LICENSE)·[제3자 고지](../../../THIRD_PARTY_LICENSES.md)를 유지한다. 신규 외부 라이브러리·BUSL 서버 코드는 도입하지 않는다.

## 호환성 영향·지원 종료

- 신규 optional namespace 추가를 제안한다. 기존 설정을 대체하거나 전체 JSON을 재생성하지 않는다.
- 알 수 없는 schema version을 쓰기로 덮어쓰지 않는다. 오래된 앱의 unknown-key round-trip 유지와 동시 설정 변경을 검증해야 한다.
- 기존 기능 제거·지원 종료는 해당 없음. 출시·지원 기간은 미정이다.
- 기능 구현자가 변경을 맡고 [SDD §6](../architecture/prd4-quick-launch-sdd.md)의 저장 보존·실행 대상·레이아웃 결과를 완료 근거로 남긴다.

## 되돌리는 조건

- 개발/설치 앱의 설정이 섞이거나, 바로가기 편집이 다른 설정을 지우거나, 다른 앱/URL이 열리면 등록/실행 기능을 비활성화한다.
- 포크 소유자가 결정을 재검토하고 기능 구현자가 UI/resolver를 비활성화한다. 저장된 entries는 삭제하지 않아 이후 복구 가능하게 한다.
- UI rollback은 이미 열린 앱·웹을 종료하지 않는다. 설정 데이터의 되돌리기는 이 namespace만 대상으로 해야 하며 전체 사용자 설정을 복원본으로 덮어쓰지 않는다.
- 재사용 기본값이 실제 작업 흐름과 맞지 않으면 정책을 조정한다. 이 변경은 서버 자동 실행이나 범용 shell 실행을 자동으로 허용하지 않는다.
