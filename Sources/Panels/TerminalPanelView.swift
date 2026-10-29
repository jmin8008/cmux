import SwiftUI
import Foundation
import AppKit
import Bonsplit
import CmuxAppKitSupportUI
import CmuxTestSupport
import CmuxTerminal
import CmuxFoundation
import CmuxSettings

/// View for rendering a terminal panel
struct TerminalPanelView: View {
    @ObservedObject var panel: TerminalPanel
    let paneId: PaneID
    let isFocused: Bool
    let isVisibleInUI: Bool
    var portalPaneOwnershipResolver: (@MainActor () -> Bool)? = nil
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
        switch panel.agentHibernationPhase {
        case .live:
            if let presentation = panel.agentWorkspace {
                AgentWorkspacePanelView(presentation: presentation, isVisible: isVisibleInUI) {
                    if let selected = presentation.selectedTerminalPanel, let lease = presentation.rendererLease {
                        nativeTerminal(selected, lease: lease)
                            .id(lease.id)
                    }
                }
            } else if let lease = panel.agentWorkspaceRendererLease, lease.isCurrent {
                Button {
                    lease.presentation?.activateRoot()
                } label: {
                    Label(String(localized: "agentWorkspace.openGroup", defaultValue: "Open agent group"), systemImage: "bubble.left.and.bubble.right")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: appearance.contentBackgroundColor))
            } else {
                nativeTerminal(panel)
            }
        case .terminating:
            Color(nsColor: appearance.contentBackgroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id("hibernation-terminating-\(panel.id.uuidString)")
        case .recovering(let hibernationState):
            AgentHibernationPlaceholderView(
                state: hibernationState,
                appearance: appearance,
                mode: AgentHibernationPlaceholderMode.recovering,
                onAction: nil
            )
            .id("hibernation-termination-recovery-\(panel.id.uuidString)")
        case .terminationFailed(let hibernationState):
            AgentHibernationPlaceholderView(
                state: hibernationState,
                appearance: appearance,
                mode: AgentHibernationPlaceholderMode.failed,
                onAction: {
                    panel.retryAgentHibernationTermination()
                }
            )
            .id("hibernation-termination-failed-\(panel.id.uuidString)")
        case .hibernated(let hibernationState):
            hibernationBody(hibernationState)
        }
    }

    @ViewBuilder
    private func hibernationBody(_ hibernationState: AgentHibernationPanelState) -> some View {
        if isVisibleInUI {
            Color(nsColor: appearance.contentBackgroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id("hibernated-resuming-\(panel.id.uuidString)")
                .onAppear {
                    onAutoResumeAgentHibernation()
                }
        } else {
            AgentHibernationPlaceholderView(
                state: hibernationState,
                appearance: appearance,
                mode: AgentHibernationPlaceholderMode.hibernated,
                onAction: onResumeAgentHibernation
            )
            .id("hibernated-\(panel.id.uuidString)")
            .onChange(of: isVisibleInUI) { _, visible in
                if visible {
                    onAutoResumeAgentHibernation()
                }
            }
        }
    }

    private func nativeTerminal(_ renderedPanel: TerminalPanel, lease: AgentWorkspaceRendererLease? = nil) -> TerminalPanelNativeView {
        let renderedPanelIsFocused = isFocused && (lease?.presentation?.terminalOwnsFocus ?? true)
        let ownershipResolver: (@MainActor () -> Bool)?
        if lease == nil {
            ownershipResolver = portalPaneOwnershipResolver
        } else {
            ownershipResolver = nil
        }

        return TerminalPanelNativeView(
            panel: renderedPanel,
            paneId: paneId,
            isFocused: renderedPanelIsFocused,
            isVisibleInUI: isVisibleInUI,
            portalPaneOwnershipResolver: ownershipResolver,
            rendererLease: lease,
            portalPriority: portalPriority,
            isSplit: isSplit,
            appearance: appearance,
            hasUnreadNotification: hasUnreadNotification,
            terminalAgentContext: terminalAgentContext,
            onFocus: onFocus,
            onResumeAgentHibernation: onResumeAgentHibernation,
            onAutoResumeAgentHibernation: onAutoResumeAgentHibernation,
            onTriggerFlash: onTriggerFlash
        )
    }

    static func effectiveTerminalAgentContext(_ context: String, pendingLaunchCommand: String?) -> String {
        TerminalPanelNativeView.effectiveTerminalAgentContext(context, pendingLaunchCommand: pendingLaunchCommand)
    }
}

private struct AgentHibernationPlaceholderView: View {
    let state: AgentHibernationPanelState
    let appearance: PanelAppearance
    let mode: AgentHibernationPlaceholderMode
    let onAction: (() -> Void)?

    private var title: String {
        switch mode {
        case .hibernated:
            String(
                localized: "terminal.agentHibernation.title",
                defaultValue: "Agent hibernated"
            )
        case .recovering:
            String(
                localized: "terminal.agentHibernation.finishing",
                defaultValue: "Finishing agent shutdown"
            )
        case .failed:
            String(
                localized: "terminal.agentHibernation.failed",
                defaultValue: "Agent shutdown needs attention"
            )
        }
    }

    private var actionTitle: String? {
        switch mode {
        case .hibernated:
            String(localized: "terminal.agentHibernation.resume", defaultValue: "Resume")
        case .recovering:
            nil
        case .failed:
            String(
                localized: "terminal.agentHibernation.retry",
                defaultValue: "Retry shutdown"
            )
        }
    }

    private var lastActivityText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: state.lastActivityAt, relativeTo: Date())
    }

    var body: some View {
        VStack(spacing: 14) {
            switch mode {
            case .recovering:
                ProgressView()
                    .controlSize(.small)
                    .accessibilityIdentifier("AgentHibernationTerminationRecoveryProgress")
            case .hibernated:
                CmuxSystemSymbolImage(magnified: "pause.circle", pointSize: 34, weight: .regular, tint: .secondary)
            case .failed:
                CmuxSystemSymbolImage(
                    magnified: "exclamationmark.triangle",
                    pointSize: 34,
                    weight: .regular,
                    tint: .secondary
                )
            }
            VStack(spacing: 4) {
                Text(title)
                    .cmuxFont(.headline)
                Text(state.agentDisplayName)
                    .cmuxFont(.subheadline)
                    .foregroundStyle(.secondary)
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "terminal.agentHibernation.lastActivity", defaultValue: "Last activity %@"),
                        lastActivityText
                    )
                )
                .cmuxFont(.caption)
                .foregroundStyle(.tertiary)
            }
            if let actionTitle, let onAction {
                Button(actionTitle) {
                    onAction()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier(
                    mode == .failed
                        ? "AgentHibernationTerminationRetryButton"
                        : "AgentHibernationResumeButton"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: appearance.contentBackgroundColor))
    }
}

/// Shared appearance settings for panels
struct PanelAppearance {
    let backgroundColor: NSColor
    let foregroundColor: NSColor
    let dividerColor: Color
    let unfocusedOverlayNSColor: NSColor
    let unfocusedOverlayOpacity: Double
    let usesClearContentBackground: Bool
    init(
        backgroundColor: NSColor,
        foregroundColor: NSColor,
        dividerColor: Color,
        unfocusedOverlayNSColor: NSColor,
        unfocusedOverlayOpacity: Double,
        usesClearContentBackground: Bool
    ) {
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.dividerColor = dividerColor
        self.unfocusedOverlayNSColor = unfocusedOverlayNSColor
        self.unfocusedOverlayOpacity = unfocusedOverlayOpacity
        self.usesClearContentBackground = usesClearContentBackground
    }

    var contentBackgroundColor: NSColor {
        usesClearContentBackground ? .clear : backgroundColor
    }

    var drawsContentBackground: Bool {
        !usesClearContentBackground
    }

    static func fromConfig(_ config: GhosttyConfig) -> PanelAppearance {
        fromConfig(
            config,
            usesTransparentWindow: WindowBackgroundComposition.policy
                .shouldUseTransparentBackgroundWindow(glassEffectAvailable: false)
        )
    }

    static func fromConfig(_ config: GhosttyConfig, usesTransparentWindow: Bool) -> PanelAppearance {
        let backgroundColor = GhosttyBackgroundTheme.color(
            backgroundColor: config.backgroundColor,
            opacity: config.backgroundOpacity
        )
        return PanelAppearance(
            backgroundColor: backgroundColor,
            foregroundColor: cmuxReadableForegroundNSColor(
                preferred: config.foregroundColor,
                on: backgroundColor
            ),
            dividerColor: Color(nsColor: config.resolvedSplitDividerColor),
            unfocusedOverlayNSColor: config.unfocusedSplitOverlayFill,
            unfocusedOverlayOpacity: config.unfocusedSplitOverlayOpacity,
            usesClearContentBackground: shouldUseClearContentBackground(
                opacity: config.backgroundOpacity,
                usesGhosttyGlassStyle: config.backgroundBlur.isMacOSGlassStyle,
                usesTransparentWindow: usesTransparentWindow
            )
        )
    }

    static func shouldUseClearContentBackground(
        opacity: Double,
        usesGhosttyGlassStyle: Bool,
        usesTransparentWindow: Bool
    ) -> Bool {
        usesTransparentWindow || usesGhosttyGlassStyle || opacity < 0.999
    }
}
