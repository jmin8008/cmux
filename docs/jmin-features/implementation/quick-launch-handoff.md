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
- titlebar 버튼 간격/별도 hit lane 회귀 테스트를 기존 `UpdatePillReleaseVisibilityTests`에 추가했다. 해당 앱 호스트 테스트는 별도 실행이 필요하다.
- Xcode 27.1에서 tagged native 앱 빌드·실행을 확인했다. 실제 NSWorkspace 앱 열기와 수정 후 재사용 검증 결과는 아래 기록한다. fullscreen/minimal 전체 모드·키보드 접근성 검증은 미실행이다.

업스트림 PR 검색에서 동일한 목록·저장·재사용 구현을 찾지 못했다. 외부 코드를 복사하거나 새 의존성을 추가하지 않았다. 기존 설치 cmux와 사용자 설정을 바꾸지 않았다.

독립 리뷰에서 store/CAS, 정확한 URL 재사용, native click 영역에 blocker가 발견되지 않았다. 실제 `QuickLaunchModel`/`Presenter`를 빌드된 CmuxSettings와 최소 host fixture로 Swift 6 typecheck하여 NSWorkspace API와 actor 접근을 확인했다. 외부에서 손상 설정을 복구한 뒤 남아 있던 오류 문구는 리뷰 의견에 따라 수정했다. 공통/기능 tag의 실제 `reload.sh --build-only`는 Ghostty 준비 후 `xcodebuild requires Xcode`에서 종료됐다.

## 네이티브 QA에서 발견한 수정

2026-10-29, macOS 27.0.1에서 `jmin-launch` (`a1fffe384`)를 실행했다. 정상 titlebar에서 알림 → 바로가기 → + 순서를 확인했고, `javascript:` URL은 저장을 거부했다. 시스템 앱 선택기로 Calculator.app을 선택하고 개발 설정에 저장하는 경로도 동작했다. About 화면에는 실제 V 아이콘이 표시됐다. 잘못된 Ghostty 설정을 별도로 수정한 뒤 기존 프로세스의 오류 알림이 사라졌다.

복원된 비활성 브라우저를 다시 여는 테스트에서 두 가지 문제가 재현됐다.

- 후보가 `BrowserPanel`만 포함하여 `DeferredBrowserPanel`인 복원 탭을 놓치고 새 탭을 만들었다. 이제 저장된 URL과 실제 materialization과 같은 profile 해석으로 후보를 만든다. 후보 조회만으로 WebKit을 모두 생성하지 않는다.
- UI에서 탭을 추가/선택한 뒤 socket의 캐시된 `surface.list`는 이전 topology/focus를 반환했다. UI mutation 완료 후 기존 `externalTopologyDidChange()` 경로로 캐시를 갱신한다.

회귀 커밋 `e5f204e47e`에서 다음 두 명령은 실제 production projection/mutation body를 Swift 6로 컴파일해 실행하고 각각 2건씩 의도한 동작 실패를 보였다. 수정 커밋 `703adeea05`에서 동일 명령이 각각 5개/2개 테스트를 통과했다. 이 경계 테스트는 native composition만 작은 fixture로 대체하며, 실제 WebKit/앱 실행을 대신하지 않는다.

```sh
python3 tests/test_quick_launch_restored_browser.py
python3 tests/test_quick_launch_topology_refresh.py
```

공통 정적 검사 17/17, 수정 Swift 문법 검사와 `git diff --check`도 통과했다. 네이티브 수정 재검증은 다음 절에 기록한다.

## 앱 열기 실패 수정과 네이티브 재검증 (2026-10-29)

**수정.** `openApp`이 실행 중인 앱의 `running.activate()`가 false이면 곧바로 실패하던 것을, 검증된 같은 URL을 `NSWorkspace.openApplication`(`createsNewApplicationInstance = false`)으로 다시 여는 것으로 바꿨다(`2df36ebe3d`). DEBUG 빌드에는 `NSError` domain/code를 `NSLog`로 남기는 계측(`quickLaunch.openApp ...`, `quickLaunch.open failed ...`)을 넣었다.

**회귀 테스트(같은 명령).** `python3 tests/test_quick_launch_app_activation.py`: `9ee19ce42c`에서 3개 중 1개 실패(`test_refused_activation_reopens_verified_app_without_new_instance`), `2df36ebe3d`에서 3/3 통과. 다른 테스트: `test_quick_launch_restored_browser.py` 5/5, `test_quick_launch_topology_refresh.py` 2/2, CmuxSettings `QuickLaunchTests` 9/9, `scripts/verify-local.py` 17/17, localization parity 11 catalogs/9 locales/0 errors.

**네이티브 빌드.** `2df36ebe3d`를 tagged `jmin-launch`로 빌드·실행(PID 9510), `ping`은 PONG.

**관찰한 것(PID 9510, 바로가기 popover를 실제 클릭).**
- Calculator 콜드 열기: Calculator 프로세스가 새로 시작됨(PID 95920), 오류 표시 없음.
- Calculator 웜 열기: 실행 중 인스턴스가 앞으로 옴, 프로세스는 1개 유지, 오류 없음. Calculator를 숨긴 뒤에도 다시 앞으로 옴.
- 웹 바로가기 `QA Launch A`: 복원된 기존 탭(surface:2)을 재사용, 새 탭 없음. `QA Launch B`: 새 탭 1개 생성, 같은 항목을 다시 열어도 추가 탭 없음. 각 URL당 탭 1개. CLI `tree --all`/`list-pane-surfaces`가 UI 탭 목록과 일치.
- 검증 후 개발 설정에서 `QA Launch A`, `QA Calculator`, `QA Launch B` 항목만 제거(`entries: []`), 다른 설정은 그대로.

**확정하지 못한 것.**
- 원래 오류가 정확히 `activate()==false` 분기였는지는 확정하지 못했다. 이 빌드에서는 Calculator 웜 열기에서 `activate()`가 성공했고 DEBUG fallback 로그(`openApp activate() returned false`)가 `log show`에서 관찰되지 않았다. fallback 동작은 production `openApp` 본문을 Swift 6로 컴파일해 실행한 회귀 테스트로만 검증했다. 콜드 실행 `openApplication` 오류 경로도 실제로는 발생하지 않았다.
- 미실행: 편집/삭제/drag 재정렬, 재시작 후 저장 복원, fullscreen/minimal, 키보드 접근성, titlebar 앱 호스트 테스트.
- GUI 자동화는 popover가 번갈아 열리지 않는 경우가 있어(앱을 먼저 앞으로 가져온 직후 클릭에서만 열림) 반복 시도를 중단했다. 이것이 위 미실행 항목의 이유다.
