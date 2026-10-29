# PRD1 implementation handoff

- Branch: `codex/browser-context`
- Base: `169da41b5d27ae811bb5dfa41a99980be97b9949`
- Worktree: `/Users/jgy/workplace/tmp/cmux-worktrees/browser-context`
- Design: [SDD](../architecture/prd1-browser-context-sdd.md), [ADR-0001](../decisions/0001-browser-context-handoff.md)
- State: implementation committed; tagged native build and focused real WebKit/PTY acceptance passed on 2026-10-29. Remaining native matrix edges are listed below.

## Implemented behavior

The browser toolbar now has a context selection toggle. It automatically chooses the single detected agent or the uniquely most recently used agent terminal in the same workspace. Input recency comes from accepted terminal input; changing focus to a dev server does not select it. Multiple unused agents require a destination selection. The active destination title stays visible and can be changed.

The isolated WebKit picker captures a clicked element or a text drag at mouse-up, once per gesture. Empty drags do not send. Image clicks include alt text only. Input/editable fields, child frames, embedded viewers, PDF and other non-HTML documents are excluded. Embedded documents, including dynamically inserted frames, have their own inline pointer hit-testing disabled while armed. Original inline value and priority are restored on removal or stop; no screen-position overlay is used for input blocking. Escape and toggle-off remove listeners and styles and restore embedded hit-testing. Design Mode, React Grab and context selection are mutually exclusive.

A bracketed text block contains a localized heading followed by JSON-quoted data: sanitized URL or HTML file URL, text, element tag, CSS selector, viewport CSS pixel bounds, viewport dimensions, and scroll offsets. JSON field names are stable interchange identifiers. Credentials, query, fragment, terminal controls and bidi controls are removed. There is no screenshot, attachment, image artifact, or inferred source-code location. Oversized selections are rejected with an explicit 32 KB error rather than truncated.

The app pins an actual terminal surface ID and document revision before arming. Navigation, browser workspace movement, replacement and close invalidate pending capture messages. A capture/target pair is claimed once before literal paste. The terminal remains in the original workspace and must still have current agent ownership evidence. There is no fallback to a focused or arbitrary terminal. The paste path uses `TerminalPanel.sendText`, never named-key or raw-input submission. No Enter is synthesized. A cold/unavailable terminal fails visibly; the latest context can be copied explicitly. Accepted input is not a claim that the agent understood it.

## Files and integration

- `Packages/macOS/CmuxBrowser/.../ContextSelection`: capture model, formatter, destination resolution, delivery gate, resource loader.
- `Packages/macOS/CmuxBrowser/.../Resources/BrowserContextSelectionRuntime.js`: the isolated click/text picker.
- `Sources/Panels/BrowserContextSelection*`: WebKit lifecycle, state and toolbar/popover.
- `Sources/Panels/BrowserPanel+ContextSelection.swift`: workspace-owned candidate and exact-terminal paste composition.
- `BrowserPanel`, `BrowserPanelView`, element-picker and teardown extensions: install/UI/lifecycle hooks.
- `TerminalPanel.recordExplicitInput`: accepted-input timestamp used for agent destination ranking.
- New app files are wired with `scripts/wire-app-sources.py`.
- 12 new localized strings have English, German, French, Arabic, Spanish, Traditional/Simplified Chinese, Korean and Japanese translations.

## Run with isolated identity

```sh
./scripts/dev-context.sh
./scripts/cli-context.sh ping
```

`dev-context.sh` fixes `CMUX_DEV_BACKEND_MODE=local` and `--tag jmin-context`. The expected bundle/config suffix is `jmin.context`, with the config under `~/.config/cmux-dev/jmin.context/`. Generic `dev-jmin.sh` is unchanged.

## Verification

Passed:

- `node --test tests/browser-context/runtime.test.cjs`: 8 actual runtime-listener behavior tests (click, text/empty drag, input/size rejection, image metadata/Escape, unsupported viewer/cancel, dynamic embed blocking/restoration, page style rewrites, and ignored click-through selection).
- `node --test tests/browser-context/frame-hit-test.test.cjs`: a real headless Chromium test with 16 checks for CSS-animation geometry changes, modal top-layer frames, dynamic iframe/object/embed insertion, style rewrites, and restored pointer input. This test fails against the pre-fix runtime and passes against the revised runtime. It skips explicitly when no Chromium binary is installed.
- `BrowserContextSelectionTests`: 5 Swift Testing tests for JSON quoting/control removal/URL sanitation, size/type rejection, local HTML text, agent ranking, stale/closed/duplicate delivery gates. The exact source and test files were symlinked into a temporary minimal SwiftPM harness to avoid unrelated SwiftUI dependencies.
- A focused `swiftc -typecheck -swift-version 6` check of the controller, WebKit message handler and toolbar against the exact new model module, with small stubs only for the existing app clipboard/style/help seams. This found and fixed WebKit's callback-only content-world evaluation overload. This is not a full app compile.
- `python3 scripts/verify-local.py --affected <base> --swift-changed <base>`: 17/17 checks.
- `python3 scripts/localization_catalog.py check`: 11 catalogs, 9 locales, zero parity errors.
- `git diff --check`, `bash -n scripts/dev-context.sh scripts/cli-context.sh`.

The localization helper also reports an existing interpolated `defaultValue` in the large touched `BrowserPanel.swift`; manual diff review confirms this feature did not add or change that string. The authoritative defaultValue and catalog checks pass.

Blocked / not claimed:

- Full `CmuxBrowser` package test compilation reaches pre-existing Bonsplit SwiftUI `@State` usage and fails because Command Line Tools lacks `SwiftUIMacros`. The failed build was stopped; no dependency source was altered.
- The tagged native app built and launched with Xcode 27.1 (build source `4b3e5eb828`, including the feature and V icon). Real click/text-drag/PTY acceptance passed as recorded below. Scroll/zoom, two-agent ambiguity and target-close/move races were not exercised natively.
- No push, PR, merge, production install or stable-cmux replacement was performed.

## Native acceptance steps

1. Run one coding-agent terminal and one dev-server terminal in the same workspace. Type in the agent, focus the server, then enable context selection in an HTML/localhost browser. Confirm the agent remains the destination.
2. Click a button and drag selected text. Confirm one bracketed block per gesture, original button/link actions suppressed, and existing input preserved. Confirm the agent does not submit until the user presses Enter.
3. Make an empty drag, click an image, scroll/zoom and select again. Confirm no image artifacts; coordinates are CSS viewport values. Check regular selection/clicks after Escape and toggle-off.
4. With two agents and no input recency, confirm target selection is required. Change target and confirm the visible title and exact terminal match.
5. Navigate/reload or close/move the target before a capture is delivered. Confirm stale captures are dropped and no other terminal receives text. Check copy fallback after a known failed insertion.
6. Toggle Design Mode and React Grab in both directions, and close/move the browser panel. Confirm no selection interception remains after teardown.

Current boundaries: only registered local agent terminals and hook-backed relay agents are auto-detected; unregistered shells and non-HTML viewers require future support. Browser portal/real input behavior remains a native smoke-test item.

## Review correction: embedded hit-testing

The initial fixed overlays could miss a moving frame and could not cover an iframe in a modal top layer. The follow-up removes those overlays and sets `pointer-events: none !important` on each embedded element itself. A mutation observer blocks new embeds and reasserts the property after page inline-style changes; teardown restores the original value and priority. Capture guards ignore the visible bounds of disabled embeds so clicks do not accidentally select underlying page content. A real Chromium hit-test fixture reproduces both reported defects against the prior commit. Native WebKit smoke validation remains pending with the app build.

## Native acceptance receipt — 2026-10-29

The built `jmin-context` app (`4b3e5eb828`) ran on macOS 27.0.1 with an isolated local HTML fixture at `127.0.0.1:18765`. A disposable terminal ran a raw PTY byte recorder with bracketed paste enabled, and its live PID was registered through the actual `set_agent_pid` socket path. This verifies terminal delivery and selection; it does not claim a real coding provider interpreted the content.

Observed:

- The toolbar automatically selected the one registered terminal. Clicking the Save settings button inserted exactly one context with its text, `#save-button`, element type, URL and CSS viewport bounds. The page's original button action did not run.
- A real pointer text drag inserted a second context with `selection: text`, `#context-text` and the exact selected sentence fragment.
- The PTY recorder received bracketed paste boundaries around each context. No CR/Enter bytes or extra key sequences appeared outside the paste. Typing `existing draft ` first and capturing again preserved those bytes and appended the third paste without submitting.
- Reloading the page disabled the picker. A pointer click inside an iframe while armed neither activated its button nor inserted context. Escape disabled the picker and the same pointer click then activated the frame button. Accessibility semantic press can directly activate an embedded button, so iframe acceptance specifically used pointer coordinates rather than the AX press shortcut.
- The original Ghostty JSON error overlay was absent after the separate configuration repair.

Evidence: `/tmp/cmux-context-native-acceptance-input.json` retains all three received contexts and raw byte boundaries; `/tmp/cmux-context-input-probe.py` is the disposable recorder. The recorder process and `codex.context-qa` PID registration were removed, and only the disposable QA workspace was closed. The development app remains usable.

Not exercised natively in this pass: two-agent target ambiguity, target closure/movement during an in-flight capture, scroll/zoom coordinates, image/size rejection, and Design Mode/React Grab mutual exclusion. Existing focused model/runtime tests cover their stated subsets; no full native acceptance matrix is claimed.
