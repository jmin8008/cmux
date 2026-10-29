# PRD2 — Drag out to a new window

- Branch: `codex/drag-out-window`
- Baseline: `169da41b5d27ae811bb5dfa41a99980be97b9949`
- Worktree: `/Users/jgy/workplace/tmp/cmux-worktrees/drag-out-window`
- Design: [SDD](../architecture/prd2-drag-out-window-sdd.md), [ADR 0002](../decisions/0002-live-panel-window-transfer.md)
- Status: implementation committed locally; native build and GUI acceptance remain pending Xcode installation.

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
