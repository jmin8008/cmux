import SwiftUI
import Foundation
import AppKit
import Bonsplit
import CmuxAppKitSupportUI
import CmuxTestSupport
import CmuxTerminal
import CmuxFoundation
import CmuxSettings

/// The reusable native body observes the actual selected panel, independently
/// of the stable group container. No surface or runtime is created here.
struct TerminalPanelNativeView: View {
    @ObservedObject var panel: TerminalPanel
    @AppStorage(NotificationPaneRingSettings.enabledKey)
    private var notificationPaneRingEnabled = NotificationPaneRingSettings.defaultEnabled
    @AppStorage(TerminalTextBoxInputSettings.maxLinesKey)
    private var textBoxMaxLines = TerminalTextBoxInputSettings.defaultMaxLines
    @AppStorage(SessionContentWidthSettings.maxWidthKey)
    private var storedSessionContentMaximumWidth = SessionContentWidthSettings.noMaximumWidth
    @AppStorage(SessionContentWidthSettings.alignmentKey)
    private var storedSessionContentAlignment = SessionContentAlignment.center.rawValue
    @State private var terminalFontSize = GhosttyConfig.loadForCmux(globalFontMagnificationPercent: GlobalFontMagnification.storedPercent).fontSize
    let paneId: PaneID
    let isFocused: Bool
    let isVisibleInUI: Bool
    var portalPaneOwnershipResolver: (@MainActor () -> Bool)? = nil
    var rendererLease: AgentWorkspaceRendererLease? = nil
    let portalPriority: Int
    let isSplit: Bool
    let appearance: PanelAppearance
    let hasUnreadNotification: Bool
    let terminalAgentContext: String
    let onFocus: () -> Void
    let onResumeAgentHibernation: () -> Void
    let onAutoResumeAgentHibernation: () -> Void
    let onTriggerFlash: () -> Void

    var body: some View {
        @Bindable var textBoxState = panel.textBoxState

        return VStack(spacing: 0) {
            if let wakeFailure = panel.agentWakeFailure {
                AgentWakeFailureBanner(
                    failure: wakeFailure,
                    onRetry: { panel.retryAgentWake() },
                    onDismiss: { panel.dismissAgentWakeFailure() }
                )
            }
            // Layering contract: terminal find UI is mounted in GhosttySurfaceScrollView (AppKit portal layer)
            // via `searchState`. Rendering `SurfaceSearchOverlay` in this SwiftUI container can hide it.
            GhosttyTerminalView(
                terminalSurface: panel.surface,
                paneId: paneId,
                isActive: isFocused,
                isVisibleInUI: isVisibleInUI,
                ownershipGeneration: panel.portalHostOwnershipGeneration,
                isCurrentPaneOwner: currentPortalPaneOwner,
                portalZPriority: portalPriority,
                showsInactiveOverlay: isSplit && !isFocused,
                showsUnreadNotificationRing: hasUnreadNotification && notificationPaneRingEnabled,
                inactiveOverlayColor: appearance.unfocusedOverlayNSColor,
                inactiveOverlayOpacity: appearance.unfocusedOverlayOpacity,
                searchState: panel.searchState,
                reattachToken: panel.viewReattachToken,
                sessionContentWidthPresentation: sessionContentWidthPresentation,
                onFocus: { _ in
                    guard currentPortalPaneOwner() else { return }
                    rendererLease?.presentation?.activateTerminal()
                    panel.terminalDidBecomeFocused()
                    onFocus()
                },
                onTriggerFlash: onTriggerFlash
            )
            // Keep the NSViewRepresentable identity stable across bonsplit structural updates.
            // This prevents transient teardown/recreate that can momentarily detach the hosted terminal view.
            .id(panel.id)
            .background(Color.clear)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
#if DEBUG
            .reportTerminalViewportGeometryForUITest(panel: panel)
#endif
            .layoutPriority(1)

            if panel.isTextBoxActive {
                TextBoxInputContainer(
                    text: $panel.textBoxContent,
                    attachments: $panel.textBoxAttachments,
                    selectedSubmitActionID: $textBoxState.selectedSubmitActionID,
                    pendingProviderLaunchAction: $textBoxState.pendingProviderLaunchAction,
                    pendingProviderLaunchStartedAt: $textBoxState.pendingProviderLaunchStartedAt,
                    surface: panel.surface,
                    terminalBackgroundColor: appearance.backgroundColor,
                    terminalForegroundColor: appearance.foregroundColor,
                    terminalFont: NSFont.monospacedSystemFont(
                        ofSize: terminalFontSize,
                        weight: .regular
                    ),
                    maxLines: TerminalTextBoxInputSettings.resolvedMaxLines(textBoxMaxLines),
                    terminalAgentContext: effectiveTerminalAgentContext,
                    shellActivityState: panel.shellActivity.state,
                    allowsCommandTemplateSubmit: TextBoxInputContainer.allowsCommandTemplateSubmit(
                        shellActivityState: panel.shellActivity.state
                    ),
                    onFocusTextBox: {
                        guard currentPortalPaneOwner() else { return }
                        rendererLease?.presentation?.activateTerminal()
                        panel.textBoxDidBecomeFocused()
                        onFocus()
                    },
                    onToggleFocus: {
                        _ = panel.focusTextBoxInputOrTerminal()
                    },
                    onSelectSubmitAction: { actionID in
                        panel.textBoxState.selectSubmitAction(actionID)
                    },
                    onRecordLaunchCommand: { command in
                        panel.recordTextBoxLaunchCommand(command)
                    },
                    onClearLaunchCommand: {
                        panel.clearTextBoxLaunchCommand()
                    },
                    onEscape: {
                        panel.handleTextBoxEscape()
                    },
                    onTextViewCreated: { view in
                        panel.registerTextBoxInputView(view)
                    },
                    onTextViewMovedToWindow: { view in
                        panel.textBoxInputViewDidMoveToWindow(view)
                    },
                    onTextViewDismantled: { view in
                        panel.preserveTextBoxContentForUnmount(from: view)
                    }
                )
                .sessionContentWidth(fillsHeight: false)
            }
        }
        .background(Color(nsColor: appearance.contentBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .ghosttyTerminalFontSizeDidChange)) { _ in
            terminalFontSize = GhosttyConfig.loadForCmux(globalFontMagnificationPercent: GlobalFontMagnification.storedPercent).fontSize
        }
    }

    private var sessionContentWidthPresentation: SessionContentWidthPresentation {
        SessionContentWidthPresentation(
            storedMaximumWidth: storedSessionContentMaximumWidth,
            storedAlignment: storedSessionContentAlignment
        )
    }

    @MainActor
    private func currentPortalPaneOwner() -> Bool {
        if let rendererLease { return rendererLease.ownsPortal(in: paneId) }
        guard panel.allowsCanonicalAgentWorkspaceRenderer, panel.agentWorkspace == nil else { return false }
        if let portalPaneOwnershipResolver {
            return portalPaneOwnershipResolver()
        }
        guard let app = AppDelegate.shared,
              let manager = app.tabManagerFor(tabId: panel.workspaceId),
              let workspace = manager.tabs.first(where: { $0.id == panel.workspaceId }),
              let livePanel = workspace.panels[panel.id],
              livePanel === panel,
              let currentPane = workspace.paneId(forPanelId: panel.id),
              currentPane.id == paneId.id,
              let tabId = workspace.surfaceIdFromPanelId(panel.id) else {
            return false
        }
        // See the resolver in WorkspaceContentView: selectedTab would
        // subscribe this update to every tab title in the pane.
        return workspace.bonsplitController.selectedTabId(inPane: currentPane) == tabId
    }

    private var effectiveTerminalAgentContext: String {
        Self.effectiveTerminalAgentContext(
            terminalAgentContext,
            pendingLaunchCommand: panel.textBoxState.pendingLaunchCommand
        )
    }

    static func effectiveTerminalAgentContext(
        _ terminalAgentContext: String,
        pendingLaunchCommand: String?
    ) -> String {
        var context = terminalAgentContext
        appendTextBoxLaunchContext(
            "textBoxPendingLaunchCommand:",
            command: pendingLaunchCommand,
            to: &context
        )
        return context
    }

    private static func appendTextBoxLaunchContext(
        _ prefix: String,
        command: String?,
        to context: inout String
    ) {
        guard let command = command?.trimmingCharacters(in: .whitespacesAndNewlines),
              !command.isEmpty else { return }
        let marker = "\(prefix)\(command)"
        let existingLines = context
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard !existingLines.contains(marker) else { return }
        if context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            context = marker
        } else {
            context += "\n\(marker)"
        }
    }
}

#if DEBUG
private extension View {
    func reportTerminalViewportGeometryForUITest(panel: TerminalPanel) -> some View {
        modifier(TerminalViewportGeometryReporter(panel: panel))
    }
}

private struct TerminalViewportGeometryReporter: ViewModifier {
    @ObservedObject var panel: TerminalPanel

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        recordTerminalViewportGeometryForUITest(proxy: proxy, panel: panel)
                    }
                    .onChange(of: proxy.size) {
                        recordTerminalViewportGeometryForUITest(proxy: proxy, panel: panel)
                    }
            }
        }
    }
}

@MainActor
private func recordTerminalViewportGeometryForUITest(proxy: GeometryProxy, panel: TerminalPanel) {
    let env = ProcessInfo.processInfo.environment
    guard env["CMUX_UI_TEST_TERMINAL_VIEWPORT_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
        return
    }

    let hostedView = panel.hostedView
    let hostedFrame = hostedView.frame
    let hostedBounds = hostedView.bounds
    let hostedSuperviewBounds = hostedView.superview?.bounds ?? .zero
    let windowContentBounds = hostedView.window?.contentView?.bounds ?? .zero
    let hostedFrameInContent: NSRect
    if let contentView = hostedView.window?.contentView {
        hostedFrameInContent = contentView.convert(hostedView.convert(hostedView.bounds, to: nil), from: nil)
    } else {
        hostedFrameInContent = .zero
    }

    _ = UITestCaptureSink().mutateJSONObjectIfConfigured(envKey: "CMUX_UI_TEST_TERMINAL_VIEWPORT_PATH") { payload in
        payload["terminalViewportPanelId"] = panel.id.uuidString
        payload["terminalViewportPanelWidth"] = terminalViewportFormat(proxy.size.width)
        payload["terminalViewportPanelHeight"] = terminalViewportFormat(proxy.size.height)
        payload["terminalViewportHostedFrameMinX"] = terminalViewportFormat(hostedFrame.minX)
        payload["terminalViewportHostedFrameMinY"] = terminalViewportFormat(hostedFrame.minY)
        payload["terminalViewportHostedFrameMaxX"] = terminalViewportFormat(hostedFrame.maxX)
        payload["terminalViewportHostedFrameMaxY"] = terminalViewportFormat(hostedFrame.maxY)
        payload["terminalViewportHostedFrameWidth"] = terminalViewportFormat(hostedFrame.width)
        payload["terminalViewportHostedFrameHeight"] = terminalViewportFormat(hostedFrame.height)
        payload["terminalViewportHostedBoundsWidth"] = terminalViewportFormat(hostedBounds.width)
        payload["terminalViewportHostedBoundsHeight"] = terminalViewportFormat(hostedBounds.height)
        payload["terminalViewportHostedSuperviewWidth"] = terminalViewportFormat(hostedSuperviewBounds.width)
        payload["terminalViewportHostedSuperviewHeight"] = terminalViewportFormat(hostedSuperviewBounds.height)
        payload["terminalViewportWindowContentWidth"] = terminalViewportFormat(windowContentBounds.width)
        payload["terminalViewportWindowContentHeight"] = terminalViewportFormat(windowContentBounds.height)
        payload["terminalViewportHostedContentMinX"] = terminalViewportFormat(hostedFrameInContent.minX)
        payload["terminalViewportHostedContentMinY"] = terminalViewportFormat(hostedFrameInContent.minY)
        payload["terminalViewportHostedContentMaxX"] = terminalViewportFormat(hostedFrameInContent.maxX)
        payload["terminalViewportHostedContentMaxY"] = terminalViewportFormat(hostedFrameInContent.maxY)
    }
}

private func terminalViewportFormat(_ value: CGFloat) -> String {
    String(format: "%.3f", Double(value))
}
#endif

