# 병렬 개발 상태 — 2026-10-29

공통 기준 커밋은 `169da41b5d27ae811bb5dfa41a99980be97b9949`이며 기본 체크아웃은 `codex/dev`다. 네 기능은 같은 기준에서 분기한 별도 worktree에 있고, 서로 합치지 않았다.

| 기능 | 브랜치 | worktree (기본 repo의 형제 폴더) | 개발 태그 |
|---|---|---|---|
| 화면 맥락 | `codex/browser-context` | `../cmux-worktrees/browser-context` | `jmin-context` |
| 창 밖 분리 | `codex/drag-out-window` | `../cmux-worktrees/drag-out-window` | `jmin-window` |
| 에이전트 작업 화면 | `codex/agent-workspace` | `../cmux-worktrees/agent-workspace` | `jmin-agents` |
| 앱·웹 바로가기 | `codex/quick-launch` | `../cmux-worktrees/quick-launch` | `jmin-launch` |

각 기능의 `docs/jmin-features/implementation/<feature>-handoff.md`에 구현 범위, 테스트 명령, native acceptance 항목이 있다. 개발 bundle/socket/config는 태그별로 분리된다. 설정 경로는 `~/.config/cmux-dev/jmin.context/`, `jmin.window/`, `jmin.agents/`, `jmin.launch/`다. 설치된 stable cmux는 교체하거나 종료하지 않았다.

## 준비한 도구

- Homebrew `mas` 7.0.0, `rustup` 1.29.2.
- Rust 1.88.0 (DiffSidecar의 clippy/rustfmt 포함), 1.95.0 (cmux-tui 지정 버전, 기본 toolchain). 두 버전 모두 arm64 및 x86_64 macOS target을 준비했다.
- 저장소 manifest와 일치하는 Zig 0.16.0. 공식 배포 SHA-256 검증 후 `/Users/jgy/workplace/tmp/cmux-toolchains/zig-aarch64-macos-0.16.0/`에 설치했다. 최신 Homebrew Zig 0.17은 호환 범위를 벗어나 제거했다.
- pin된 GhosttyKit을 저장소 체크섬 검증 경로로 받아 공통 캐시에 준비했다.
- 로컬 toolchain 환경: `source /Users/jgy/workplace/tmp/cmux-toolchains/env.sh`. Xcode.app이 설치되면 이 파일이 해당 DEVELOPER_DIR를 선택한다.

## 아직 막힌 항목

전체 Xcode가 없고 Command Line Tools만 있다. App Store ‘받기’는 설치 확인 시트가 두 차례 비어 있는 상태로 멈췄다. `mas install 497799835`는 관리자 인증이 필요했고, Apple 공식 직접 다운로드는 인증되지 않은 요청을 거부했다. 사용자에게 Mac의 App Store에서 설치·인증을 완료해 달라고 요청했다. 비밀번호는 받지 않았다.

실제 `scripts/dev-jmin.sh --build-only`와 `scripts/dev-jmin-launch.sh --build-only`는 Ghostty 준비 후 `xcodebuild requires Xcode`에서 실패했다. 정적 검사와 작은 패키지 테스트를 통과한 사실을 앱 빌드/실행 완료로 표시하지 않는다.

Xcode 설치 후 Metal Toolchain을 준비하고 `scripts/setup.sh`를 마친 다음 태그별로 빌드·실행해야 한다. 전체 앱 빌드는 한 번에 하나씩 진행한다. 검증 전 기능을 통합하거나 배포하지 않는다.

## 로컬 의존성 변경

창 분리 기능은 `vendor/bonsplit`의 로컬 커밋 `3316685ac4170ddab29b85f56c136f98d22a58a3`을 사용한다. 원격에는 올리지 않았으며 `.git/jmin-feature-coordination/drag-out-window-bonsplit.bundle`에 복구 가능한 bundle을 남겼다. 원격 공유 시에는 이 의존성도 접근 가능한 fork에 게시해야 한다. 현재 worktree에서의 빌드에는 로컬 객체가 준비되어 있다.

## 검증된 로컬 커밋

- 화면 맥락: `f9d74ff13c` (기본 구현 `bb6fc3e067` + iframe 입력 차단 보완). JavaScript 9개 테스트(실제 Chromium 16개 점검 포함), Swift 모델 5개, 정적 검사 17개 통과.
- 창 분리: `cc3b13b3aa`. 정책 6개·sidebar 5개 테스트, 정적 검사 17개 통과. 4개 native integration test는 Xcode 대기.
- 바로가기: `6743411abc`. CmuxSettings 테스트 9개·정적 검사 17개 통과. 독립 리뷰의 설정 복구 오류 메시지 문제 수정.
- 에이전트 작업 화면: 구현·검증 진행 중. 대화/원본 root terminal 전환과 관찰된 child 기록, native 키보드/포커스 경로를 연결했다. 실제 Teams 관계 및 자동 그룹 진입 경로를 추가 확인 중이다.
