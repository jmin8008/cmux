# PRD2 — Drag out to a new window

- Branch: `codex/drag-out-window`
- Baseline: `169da41b5d27ae811bb5dfa41a99980be97b9949`
- Worktree: `/Users/jgy/workplace/tmp/cmux-worktrees/drag-out-window`
- Design: [SDD](../architecture/prd2-drag-out-window-sdd.md), [ADR 0002](../decisions/0002-live-panel-window-transfer.md)
- Status: native application build passed; the first live drag check exposed a startup callback wiring defect, now repaired with a focused regression. Native acceptance must be repeated on the repaired build.

## Behavior

A confirmed mouse release outside every visible window of this process moves the source into a new window near that point. Accepted internal drops take priority. Escape, missing release evidence, invalid/stale capabilities and repeated native completions do not create a window. Negative display coordinates and usable screen bounds are handled by a pure placement policy.

Workspace-pane terminal, browser, file-preview and Markdown panels reuse `AppDelegate.moveSurface`. The same live panel, terminal surface and browser webview move between owners. The target window is prepared before detach and its bootstrap panel is closed after successful attach. The existing empty-source workspace/window policy applies. An opt-in reversible detach keeps an emptied source pane until attach commits; failure reattaches at the original pane/index and restores the original focused panel.

Whole workspace drags reuse `moveWorkspaceToNewWindow`: the workspace object, split controller, tab order and panels stay intact. Both the AppKit table and the alternate native sidebar source call the same generation-fenced registry completion path. A new “New Window” destination in the panel Move menu invokes the same panel operation.

Unsupported providers (including Dock-owned tabs and Chief panels) are rejected with the existing localized Move Failed alert. Group/multi-workspace table drags retain their existing behavior; they do not partially detach an anchor as a single workspace. No cross-process transfer, terminal restart or snapshot-based session recreation was introduced.

## Source and dependency changes

- `DragOutWindowPolicy`: completion classification and usable-screen placement in CmuxFoundation.
- `DragOutWindowCoordinator`: local mouse-up/Escape evidence and window placement. It observes events without consuming them; unknown native outcomes leave ownership untouched.
- `AppDelegate+DragOutWindow`: live panel move and failure feedback.
- Bonsplit: a live-capability completion callback after native source cleanup; optional preservation of an empty pane during a reversible close.
- CmuxSidebar: exact-session/capability validation and completion after registry cleanup.
- Existing AppDelegate/Workspace/sidebar composition and menu routes are connected to these paths.

Bonsplit commit: `3316685ac4170ddab29b85f56c136f98d22a58a3` (local branch `codex/drag-out-window`). The parent gitlink records this local commit. It is **not available from upstream** until separately published. A recoverable bundle is saved outside tracked files at:

`/Users/jgy/workplace/tmp/cmux/.git/jmin-feature-coordination/drag-out-window-bonsplit.bundle`

When checking out this feature in another local checkout, fetch the bundle into that checkout's initialized Bonsplit repository before updating the submodule:

```sh
git -C vendor/bonsplit fetch /Users/jgy/workplace/tmp/cmux/.git/jmin-feature-coordination/drag-out-window-bonsplit.bundle codex/drag-out-window
git submodule update --init vendor/bonsplit
```

An upstream open-PR search for `drag new window` was performed before implementation. The returned sidebar organization PR (#18334) and NEXT-specific drag work did not provide this native completion/tear-off path at the baseline.

## Validation observed

- `python3 scripts/verify-local.py --swift-changed 169da41b5d27ae811bb5dfa41a99980be97b9949`: **17/17 checks passed**, including source/test wiring, localization, launch policy and project normalization. The final failure-feedback and handoff state was checked again with the same 17/17 result.
- `DragOutWindowPolicyTests`: **6 tests passed**, including a parameterized test with four cancellation/acceptance combinations. Executed in `/tmp/cmux-prd2-policy-tests`, a minimal SwiftPM harness containing the actual policy source and its committed tests.
- `SidebarWorkspaceDragOutCompletionTests` plus existing `SidebarWorkspaceDragRegistryNativeLifecycleTests`: **5 tests passed** in `/tmp/cmux-prd2-sidebar-tests`. This harness symlinks the actual CmuxSidebar Drag sources and tests, depending on the real CmuxFoundation package; no replacement registry implementation is used. CoreDrag emitted diagnostic `-1850` for the existing fake dragging sessions; the five assertions suites completed successfully.
- `DragOutWindowCoordinator.swift`: standalone typecheck passed with Swift 6 and the compiled CmuxFoundation module.
- Changed Bonsplit Swift files: syntax parse passed. **Full Bonsplit tests did not compile** because the installed Command Line Tools lack `SwiftUIMacros.StateMacro` required by existing SwiftUI views.
- **Full CmuxFoundation test-target compilation is blocked** by existing SSHAgentSocketResolverTests/SSHPTYReplayOutputFilterTests expressions that the installed compiler cannot typecheck in reasonable time. The library target compiled; the focused policy harness passed.
- New app integration tests are wired in `cmuxTests/DragOutWindowTransferTests.swift`: failed-attach rollback retains split/panel identity; new terminal window retains the TerminalSurface; browser retains WKWebView; entire workspace retains layout and object identity. **They have not been compiled or executed without Xcode.**
- `bash -n scripts/dev-jmin-window.sh`, `git diff --check`, and the catalog validator passed.
- `localize-changes` prepared zero new keys and reported only existing interpolated-defaultValue review warnings in large AppDelegate/Workspace files. New Window / Move Failed / OK reuse existing catalog keys; all required nine locales were checked. Catalog result: **11 catalogs, 9 locales, 0 parity errors**.

Logs remain in `/tmp/cmux-prd2-{verify-local,foundation-tests,bonsplit-tests,policy-tests,sidebar-tests,localization}.log`.

## Build and acceptance after Xcode is available

Use the assigned build slot only:

```sh
./scripts/dev-jmin-window.sh
CMUX_TAG=jmin-window scripts/cmux-debug-cli.sh list-windows
```

The wrapper fixes `--tag jmin-window` and `CMUX_DEV_BACKEND_MODE=local`. Its isolated config namespace is `~/.config/cmux-dev/jmin.window/`. The generic `dev-jmin.sh` is unchanged. Do not run the stable installation or the global `/tmp/cmux-cli` helper.

Compile/run the four new app tests through `scripts/test-unit.sh` with a separate tagged test DerivedData directory. Then verify in the running tagged app:

1. Native drag of a running terminal to the desktop: one new window, same panel/process/TTY and continuing output; both sole-panel and multi-panel source cases.
2. Browser with navigation history, form/scroll state; file and Markdown preview. Move-menu behavior should match dragging.
3. Workspace with multiple splits and reordered tabs: identical workspace ID/layout/panel IDs.
4. Escape during drag, unsupported target inside another cmux window, accepted cross-window drop, duplicate end callback: no extra window or ownership change.
5. Negative-origin second display, Dock/menu-bar edge and fullscreen source: accessible destination title bar and correct focus.
6. Inject destination tab-creation rejection via `failedAttachRestoresSamePanelInOriginalSplit`: same source panel, original pane/index/focus, and no copied session. Confirm an unsuccessful new-window transfer closes its bootstrap target.
7. First native check must confirm that AppKit supplies fresh mouse-up evidence on this macOS version. The implementation deliberately declines a tear-off when the native loop exposes neither a local mouse-up nor a current mouse-up event.

No native app build, launch or visual verification is claimed by this handoff. No feature merge, push or external PR was performed.

## 2026-10-29 native verification and startup repair

The `b844fe58d9` tagged application compiled and launched with its isolated socket.
A terminal in `PRD2 native QA` reported shell PID `21939`, TTY `ttys015`, and a
session marker before dragging. Two native outside drops started a Bonsplit drag
but did not create a new window. Escape cleared the drag state and retained the
same panel `4B5731C3-7F2C-4561-BC50-471301072386` and terminal contents.

The initial `TabManager` creates its registry before `AppDelegate.configure`
adopts it. The original drag-out callback was installed only by the delegate's
registry-creation getter, so adoption skipped the callback. Creation and adoption
now use the same weak-owner callback installer.

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 tests/test_drag_out_bootstrap_registry.py`
executes the actual production registry/adoption bodies with only UI effects
substituted. At red commit `833e0a9e1d`, the bootstrap completion reached zero
handlers and moved no panel while the created-registry case passed. With the fix,
both cases pass and releasing the delegate succeeds (no callback retain cycle).
This validates startup wiring; it does not establish native mouse-release evidence.

Rebuilt native drag, browser/preview continuity, cross-window acceptance, and
whole-workspace layout checks remain pending. Logs and tree snapshots are under
`/tmp/cmux-prd2-native-qa/`.

## 2026-10-29 rebuilt-app verification (observed vs not run)

Build: tagged app `jmin-window` rebuilt from `0f95dbc047` (`dev-jmin-window.sh --launch`, BUILD SUCCEEDED, `ping` = PONG, app PID 77649). Earlier rebuild at `f17b77478c` was replaced by this one.

### Defects found and fixed this session
1. `cmuxTests/DragOutWindowTransferTests.swift` did not compile: `Tab` ambiguous in the rejecting delegate. Fixed by `Bonsplit.Tab` (`39849d43a4`).
2. **Real production defect** found by the app-host tests (2 of 4 red, `target.panels.count == 2`: `ChiefPanel` + moved panel): a new window starts as `[Chief home, bootstrap Terminal]`, but `moveSurfaceToNewWindow` used `tabs.first` (the Chief home) as the target, so the dragged panel landed beside the Chief panel and the bootstrap terminal stayed. Fixed to use the first non-Chief-home workspace (`0f95dbc047`). Same command red -> green.

### App-host tests (runner `--profile window`; plan, clone, settings, build, run)
- `settings` verified; the cloned cache needed its stale `ModuleCache.noindex` moved aside (absolute module-cache path mismatch from the APFS clone).
- Red (`63754b4700`): 4 executed, 2 passed, 2 failed (xcresult summary). Green (`0f95dbc047`): **4 executed, 4 passed, 0 failed** (`failedAttachRestoresSamePanelInOriginalSplit`, `newWindowKeepsTheTerminalSurfaceAndRemovesBootstrap`, `newWindowKeepsBrowserWebViewObject`, `entireWorkspaceKeepsSplitAndPanelIdentity`) plus the isolation test. `verify-local.py`: 17/17.

### Real drag, observed on `0f95dbc047` (cmux-cua foreground drag)
- Terminal tab dragged outside every window: one new window created at (100, 267) near the drop point; surface `surface:1000030006` unchanged id; shell PID 79020 / `ttys013` before and after, marker output continued (tick 1-7 before, 41+ after, no restart). Mouse-up was classified as a release (a window was created).
- Cross-window accept: browser tab dropped on another cmux window moved into it (source workspace removed under the empty-source policy); no extra window.
- Browser outbound drag to empty desktop: new window created; JS state (`window.__prd2`) and URL preserved, i.e. same WKWebView; `scrollY` went 200 -> 0 (not investigated).

### Not verified
- Whole-workspace/sidebar drag-out: two synthetic drags from a sidebar row produced no window and the log never showed `hasSidebarDrag=1`; the sidebar drag session apparently did not start from synthetic events. This is neither a pass nor a confirmed defect. The unit test for layout preservation passes.
- Escape cancel on this build: cua `drag` is atomic, no key can be sent mid-drag. Escape preservation was only observed on the pre-fix `b844fe58d9` build.
- File/Markdown preview drag; negative-origin display, fullscreen source; duplicate end callback; multi-panel sole-vs-multi source beyond the terminal+browser case.
