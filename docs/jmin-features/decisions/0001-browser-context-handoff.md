---
title: ADR-0001 화면 선택 맥락을 명시적인 터미널 대상으로 전달
type: decision
date: 2026-10-29
author: jmin8008 (설계 초안 작성 지원 Codex)
status: accepted
issue:
tags: [decision, prd1, browser-context, jmin-fork]
---
# ADR-0001 화면 맥락 수집과 터미널 전달의 분리

> 한 줄 요약: 클릭·드래그한 맥락을 대화하던 에이전트에 대괄호 텍스트로 삽입하고 사용자가 요청을 덧붙여 제출하는 흐름을 채택한다. 대상: 사람(의사결정).

## 문제 (Why now)

웹에서 보고 있는 위치와 내용을 설명하려면 URL 복사, 화면 캡처, 터미널 전환을 반복해야 한다. 사용자는 클릭·드래그한 맥락을 토글로 곧바로 터미널에 넣는 개인 개발용 기능을 요구했다.

현재 Design Mode에는 선택·캡처·formatter가 있고 React Grab에는 반환 터미널을 찾아 입력하는 경로가 있다. 요소 수집·formatter만 재사용하는 텍스트 경로를 연결하면서 잘못된 목적지, 오래된 선택, 중복 입력을 방지하는 계약이 필요하다.

## 제약·비목표

- 실행 환경·지원 뷰어는 [SDD §1·§4](../architecture/prd1-browser-context-sdd.md) 참조.
- 2026-10-29 사용자가 내부 브라우저·localhost·HTML, 클릭/drag 자동 구분, 실제 대괄호 텍스트를 확정했다. 별도 선택 모드 UI는 만들지 않고 사각형 영역·이미지 전달은 1차에서 제외한다.
- 일반 터미널에서는 `[맥락]`을 텍스트로 표현한다. 클릭 가능한 chip은 이번 범위가 아니다.
- DOM 위치에서 소스 파일·행 번호를 추정하지 않는다. 확인된 source map 등의 근거가 있을 때만 추가한다.
- 외부 앱 수집과 새로운 에이전트 실행기는 제외한다. 방금 대화하던 에이전트로 자동 연결하고 삽입만 수행하며 제출은 사용자가 한다.

## 선택지 (최소 2개)

| 안 | 요지 | 복잡도 | 장점 | 단점·위험 |
|---|---|---|---|---|
| A (최소안) | 기존 클립보드 복사 후 수동 붙여넣기 | 낮음 | 재사용 범위가 큼 | 직접 삽입 요구를 충족하지 못함 |
| B (채택 방향) | 기존 요소 수집기 + 자동 gesture 구분 + 텍스트 전달 | 중간 | 직접 전달, 이미지 없는 출처·본문 | 대상 수명·중복·입력 정책 처리가 필요 |
| C | 모든 화면을 캡처하고 OCR로 해석하는 공통 도구 | 높음 | 외부 앱까지 확장 가능 | 접근성/화면 권한, OCR 오류, 불필요한 수집 범위 |

## 결정

**채택: B의 제품 동작과 연결 방향.** 2026-10-29 구체적인 전달 예시를 설명한 뒤 사용자가 동의했다. accepted는 동작·설계 방향의 채택을 뜻하며 세부 타입/API의 확정이나 구현·검증 완료를 뜻하지 않는다.

- 토글 ON에서 클릭은 요소, 텍스트 selection이 생긴 drag는 문장으로 판정한다. 별도 모드 선택을 요구하지 않으며 빈 영역 drag는 무전달이다.
- 같은 workspace에서 대화하던 agent 터미널에 자동 연결한다. 표시·변경 방법과 후보가 모호할 때의 행동은 세부 구현에서 정한다.
- 직접 전달은 literal paste만 수행하고 사용자가 요청 문장을 덧붙여 제출한다. 맥락 선택만으로 Enter/제출 키를 보내지 않는다.
- 기존 URL 정제는 유지한다. 새로운 맥락 기능은 이미지/JSON 첨부 파일이나 artifact lease를 요구하지 않는다. 기존 Design Mode의 이미지 기능은 이 기능과 분리해 유지한다.
- 같은 capture의 입력 결과가 불명확한 경우 자동 재시도로 중복 프롬프트를 만들지 않는다.

최소안 A로는 직접 삽입 목표를 달성할 수 없으므로 coordinator의 복잡도를 수용한다. 외부 앱 지원·원격 첨부 업로드·입력 chip은 실제 요구와 어댑터가 확보될 때 별도 결정한다.

## 결과·영향

- 변경 영역은 `Sources/Panels/`, `CmuxBrowser/DesignMode`, 기존 터미널 입력 연결이다. 새 원격 socket 명령은 도입하지 않는다.
- PRD2의 창 이동과는 terminal panel identity를 공유한다. window ID나 현재 포커스만으로 대상을 식별하지 않는다.
- PRD3가 없어도 일반 터미널 대상으로 독립 구현·검증할 수 있다. PRD4는 의존성이 없다.
- 구현 순서 제안은 envelope/formatter → 목적지·전달 → picker UI → 뷰어별 확장이다. 구체 태스크 파일·커밋은 이번 문서 요청 범위에 포함하지 않는다.

## 시기·적용 한계·출처

- 작성·조사·채택일: 2026-10-29. 채택 근거는 전달 예시와 PRD3 사용 장면 설명 뒤의 사용자 동의다. 적용 목표 시기: 미정.
- 요구 근거: 같은 날짜 대화의 PRD1. 기준 HEAD `ef3d1307e116d1c0ba3c6f5ea124a6d28f6c01fe`; 작업 트리에 다른 변경이 있으며 구현 시작 때 다시 확인한다.
- 근거 코드: [picker](../../../Sources/Panels/BrowserPanel+ElementPicker.swift), [handoff](../../../Sources/Panels/BrowserDesignModeController+Handoff.swift), [URL·prompt context](../../../Packages/macOS/CmuxBrowser/Sources/CmuxBrowser/DesignMode/BrowserDesignModePromptContext.swift), [AppDelegate](../../../Sources/AppDelegate.swift).
- 외부 출처·라이선스: 위 저장소 코드를 설계 근거로 참조했으며 외부 코드를 복사하지 않았다. [LICENSE](../../../LICENSE)와 [제3자 고지](../../../THIRD_PARTY_LICENSES.md)를 유지한다. 서버 디렉터리의 코드는 사용하지 않는다. 별도 신규 외부 라이브러리는 제안하지 않는다.

## 호환성 영향·지원 종료

- 기존 Design Mode/React Grab 사용자, 터미널 입력 경로가 영향 대상이다. OFF 상태와 기존 복사 방식은 유지한다.
- `ContextEnvelope v1`은 제안된 내부 모델이다. 기존 공개 JSON/socket 계약을 교체하지 않는다.
- 지원 기간·출시일은 미정이며 기존 API의 지원 종료는 해당 없음: 제거를 제안하지 않는다.
- 구현 담당은 해당 기능 브랜치 작업자, 완료 확인은 [SDD §6](../architecture/prd1-browser-context-sdd.md) 기준이다.

## 되돌리는 조건

- 오입력·중복 입력·자동 실행이 발생하거나 기존 페이지 조작을 복구하지 못하면 직접 전달을 비활성화하고 복사 경로로 돌아간다.
- 결정 재검토 담당: 포크 소유자. 복구 실행 담당: 기능 구현자.
- 비용: 토글과 terminal sink를 분리했으므로 구조 변경 범위는 제한된다. 이미 터미널에 전달한 텍스트나 그 후 사용자가 실행한 작업은 자동 회수할 수 없다. 1차 기능 자체는 이미지 artifact를 남기지 않는다.

미결과 실제 검증 상태는 [SDD](../architecture/prd1-browser-context-sdd.md)에 기록한다.
