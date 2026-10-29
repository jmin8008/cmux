# PRD4 바로가기 구현

- 브랜치: `codex/quick-launch`
- 기준: `169da41b5d27ae811bb5dfa41a99980be97b9949`
- 개발 태그: `jmin-launch`; 설정: `~/.config/cmux-dev/jmin.launch/cmux.json`
- 실행: `./scripts/dev-jmin-launch.sh --launch`; CLI: `./scripts/cli-jmin-launch.sh ping`

알림과 + 사이의 공통 titlebar control에 바로가기 목록을 연결했다. 일반·fullscreen·minimal 표시와 native click proxy/window monitor의 hit region이 같은 슬롯을 쓴다. 목록에서 웹·설치 앱을 추가하고, 우클릭으로 수정/삭제/순서 이동하거나 항목을 드래그해 순서를 바꾼다. 웹은 cmux 내부/기본 브라우저 중 선택하며 현재 페이지로 폼을 채울 수 있다. 앱은 `.app` 선택기로 등록한다. 이름과 SF Symbol 아이콘을 편집할 수 있다.

앱 전체 공통 목록을 `quickLaunch.version=1` namespace에 저장한다. `JSONConfigStore` writer lock 안에서 최신 문서에 항목별 mutation을 적용한다. 동시 추가는 보존하고 같은 항목의 오래된 수정/삭제는 충돌로 거부한다. 다른 설정·주석을 유지한다. 중복 ID, 손상 파일, 모르는 version/field는 쓰지 않는다. 파일 관찰이 다른 창의 변경과 손상 상태를 반영한다. 설정 위치는 공통 `CmuxConfigLocation`을 사용한다.

웹 재사용 순서는 같은 workspace/profile의 유효한 binding → 현재 선택된 정확한 URL 일치 panel → UUID 순의 정확한 일치 panel이다. query/fragment를 포함해 비교한다. 다른 URL로 이동한 panel은 변경하지 않는다. 앱은 선택 경로·bookmark·bundle ID를 확인하고 그 경로의 실행 중 앱을 활성화하거나 NSWorkspace로 연다. 앱 이동/삭제 또는 오래된 bookmark는 재선택 오류로 표시한다. 외부 브라우저 탭 재사용은 OS에 맡긴다. localhost 서버는 시작하지 않는다.

첫 구현의 내부 브라우저 실행은 로컬 workspace에 한정한다. remote/cloud workspace에서 localhost가 다른 머신으로 변환되지 않도록 거부하며, 이 경우 등록 폼의 기본 브라우저 옵션을 쓸 수 있다. 별도 keyboard shortcut이나 자동 favicon 다운로드는 없다. popover의 최소 폭은 360pt이다.

## 검증

- CmuxSettings `QuickLaunchTests`: 9 tests 통과. 5개 위험/불완전 URL, 3개 손상 문서 사례 포함. 실제 temp JSON에 두 store가 동시 추가하는 테스트, 주석·다른 설정 보존, 미래 버전/미지 필드 보존, 오래된 수정 충돌, reorder, workspace/profile/query 재사용 범위를 검사했다.
- `python3 scripts/verify-local.py --swift-changed`: 17/17 통과(문법, localization, schema, Xcode 파일 wiring 등). 앱 컴파일과 실행을 대신하지 않는다.
- `python3 scripts/localization_catalog.py check`: 11 catalogs, 9 locales, 0 parity errors. 신규 26개 key를 번역했다. `localize-changes`는 기존 Workspace.swift의 interpolated defaultValue parser 경고 때문에 exit 1이며 번역 import/strict parity는 통과했다.
- titlebar 버튼 간격/별도 hit lane 회귀 테스트를 기존 `UpdatePillReleaseVisibilityTests`에 추가했다. 네이티브 테스트 실행은 Xcode 설치 대기다.
- 네이티브 빌드, 실제 NSWorkspace 앱 열기, 모든 모드의 화면/드래그·키보드 접근성 확인은 아직 미완료다. CLT만 설치된 환경에서는 완성 앱이라고 판정하지 않는다.

업스트림 PR 검색에서 동일한 목록·저장·재사용 구현을 찾지 못했다. 외부 코드를 복사하거나 새 의존성을 추가하지 않았다. 기존 설치 cmux와 사용자 설정을 바꾸지 않았다.

독립 리뷰에서 store/CAS, 정확한 URL 재사용, native click 영역에 blocker가 발견되지 않았다. 실제 `QuickLaunchModel`/`Presenter`를 빌드된 CmuxSettings와 최소 host fixture로 Swift 6 typecheck하여 NSWorkspace API와 actor 접근을 확인했다. 외부에서 손상 설정을 복구한 뒤 남아 있던 오류 문구는 리뷰 의견에 따라 수정했다. 공통/기능 tag의 실제 `reload.sh --build-only`는 Ghostty 준비 후 `xcodebuild requires Xcode`에서 종료됐다.
