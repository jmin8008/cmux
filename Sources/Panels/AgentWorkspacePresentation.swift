import AppKit
import CmuxBrowser
import Foundation
import Observation
import WebKit

/// A presentation of existing terminal sessions. It never starts or stops them.
@MainActor
@Observable
final class AgentWorkspacePresentation: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let rootPanelID: UUID
    let rootSessionID: String
    let rootProvider: String
    let webView: CmuxWebView
    private(set) var rendererLease: AgentWorkspaceRendererLease?
    var selectedTerminalPanel: TerminalPanel? {
        guard let rendererLease, rendererLease.isCurrent else { return nil }
        return rendererLease.panel
    }
    var showsTerminal: Bool { selectedTerminalPanel != nil }
    private(set) var terminalOwnsFocus = false
    var showsFind = false
    var findNeedle = ""
    private weak var workspace: Workspace?
    private let baseURL: URL
    private let defaults: UserDefaults
    let sessionService: AgentChatTranscriptService?
    private var sessionObservation: AgentWorkspaceSessionObservation?
    private var selectionKey: String { "agentWorkspace.selection.v1.\(rootProvider).\(rootSessionID)" }

    init(
        workspace: Workspace,
        rootPanelID: UUID,
        rootSessionID: String,
        rootProvider: String,
        url: URL,
        defaults: UserDefaults = .standard,
        sessionService: AgentChatTranscriptService? = nil
    ) {
        self.workspace = workspace
        self.rootPanelID = rootPanelID
        self.rootSessionID = rootSessionID
        self.rootProvider = rootProvider
        self.baseURL = url.deletingLastPathComponent().deletingLastPathComponent()
        self.defaults = defaults
        self.sessionService = sessionService ?? TerminalController.shared.agentChatTranscriptService
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let key = "agentWorkspace.selection.v1.\(rootProvider).\(rootSessionID)"
        if let saved = defaults.string(forKey: key),
           let data = saved.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            configuration.userContentController.addUserScript(WKUserScript(
                source: "window.__AGENT_WORKSPACE_SELECTION__ = \(saved);",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }
        self.webView = CmuxWebView(frame: .zero, configuration: configuration, host: CmuxWebViewAppHost())
        super.init()
        if let service = self.sessionService {
            sessionObservation = AgentWorkspaceSessionObservation(service: service) { [weak self] in
                self?.revalidateSessionBindings()
            }
        }
        // The content controller retains handlers; the proxy avoids a cycle.
        configuration.userContentController.add(AgentWorkspaceMessageProxy(self), name: "cmuxAgentWorkspace")
        webView.navigationDelegate = self
        webView.load(URLRequest(url: url))
    }

    func hasCurrentSessionBindings(panelID: UUID, sessionID: String, provider: String) -> Bool {
        sessionService?.sessionBindingMatches(surfaceID: rootPanelID, sessionID: rootSessionID, provider: rootProvider) == true
            && sessionService?.sessionBindingMatches(surfaceID: panelID, sessionID: sessionID, provider: provider) == true
    }

    /// Called synchronously for registry changes, including PID exit and rebind.
    /// Retain the selected conversation, but withdraw raw input ownership now.
    func revalidateSessionBindings() {
        guard let lease = rendererLease, !lease.isCurrent else { return }
        let restoreWebFocus = terminalOwnsFocus && workspace?.focusedPanelId == rootPanelID
        releaseRenderer()
        if restoreWebFocus { focus() }
        let rootIsCurrent = sessionService?.sessionBindingMatches(
            surfaceID: rootPanelID, sessionID: rootSessionID, provider: rootProvider
        ) == true
        webView.evaluateJavaScript("window.dispatchEvent(new CustomEvent('cmux-agent-workspace-binding-lost', { detail: { rootInvalid: \(!rootIsCurrent) } }));", completionHandler: nil)
    }

    func focus() {
        terminalOwnsFocus = false
        selectedTerminalPanel?.unfocus()
        guard let window = webView.window, !webView.isHiddenOrHasHiddenAncestor else { return }
        if let responder = window.firstResponder as? NSView,
           responder === webView || responder.isDescendant(of: webView) { return }
        window.makeFirstResponder(webView)
    }

    func activateRoot() {
        guard let workspace, workspace.focusedPanelId != rootPanelID else { return }
        workspace.focusPanel(rootPanelID)
    }

    func activateTerminal() {
        guard selectedTerminalPanel != nil else { return }
        terminalOwnsFocus = true
        activateRoot()
    }

    func webContentDidBecomeFocused() {
        terminalOwnsFocus = false
        selectedTerminalPanel?.unfocus()
        activateRoot()
    }

    /// Find belongs to web content unless the actual terminal owns focus.
    var routesFindToWebContent: Bool {
        !showsTerminal || showsFind || !terminalOwnsFocus
    }

    func hideTerminal() {
        releaseRenderer()
        focus()
    }

    /// Called only after the bridge has validated the current session registry.
    /// Unsupported owners keep the existing focus-at-source fallback.
    @discardableResult
    func showTerminal(panel: TerminalPanel, sessionID: String, provider: String) -> Bool {
        guard hasCurrentSessionBindings(panelID: panel.id, sessionID: sessionID, provider: provider),
              let workspace, workspace.layoutMode != .canvas, workspace.isPortalRenderingEnabled,
              let root = workspace.terminalPanel(for: rootPanelID), root.agentWorkspace === self,
              let rootPane = workspace.paneId(forPanelId: root.id),
              let rootTab = workspace.surfaceIdFromPanelId(root.id),
              workspace.bonsplitController.selectedTabId(inPane: rootPane) == rootTab,
              workspace.bonsplitController.zoomedPaneId.map({ $0 == rootPane }) ?? true,
              workspace.panels[panel.id] === panel, panel.workspaceId == workspace.id,
              workspace.remoteTmuxWindowMirrors[root.id] == nil,
              workspace.remoteTmuxWindowMirrors[panel.id] == nil,
              workspace.paneId(forPanelId: panel.id) != nil,
              case .live = root.agentHibernationPhase, case .live = panel.agentHibernationPhase,
              root.cloudAttachment == nil, root.deviceAttachment == nil,
              panel.cloudAttachment == nil, panel.deviceAttachment == nil,
              panel.surface.canAcceptPortalBinding(expectedSurfaceId: panel.id, expectedGeneration: nil),
              panel.agentWorkspace == nil || panel === root,
              panel.agentWorkspaceRendererLease == nil || panel.agentWorkspaceRendererLease?.presentation === self
        else { return false }
        if panel === root, sessionID != rootSessionID || provider != rootProvider { return false }
        if let current = rendererLease, current.isCurrent, current.panel === panel,
           current.sessionID == sessionID, current.provider == provider {
            showsFind = false
            terminalOwnsFocus = true
            return true
        }
        releaseRenderer()
        root.unfocus()
        root.hostedView.setVisibleInUI(false)
        TerminalWindowPortalRegistry.hideHostedView(root.hostedView)
        panel.unfocus()
        panel.recordPortalHostOwnershipChange()
        let lease = AgentWorkspaceRendererLease(
            workspace: workspace, root: root, panel: panel, presentation: self,
            sessionID: sessionID, provider: provider
        )
        rendererLease = lease
        panel.agentWorkspaceRendererLease = lease
        showsFind = false
        terminalOwnsFocus = true
        workspace.scheduleTerminalGeometryReconcile()
        return true
    }

    func releaseRenderer() {
        let previous = rendererLease
        // Revocation precedes publishing the replacement; old callbacks see
        // their lease as invalid even if SwiftUI dismantles them much later.
        previous?.revoke()
        rendererLease = nil
        terminalOwnsFocus = false
    }

    func startFind() { showsFind = true }

    func hideFind() {
        showsFind = false
        webView.find("", configuration: WKFindConfiguration()) { _ in }
        focus()
    }

    func find(backwards: Bool = false) {
        guard !findNeedle.isEmpty else { return }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.wraps = true
        webView.find(findNeedle, configuration: configuration) { _ in }
    }

    func findSelection() {
        webView.evaluateJavaScript("window.getSelection()?.toString() ?? ''") { [weak self] value, _ in
            guard let self, let text = value as? String, !text.isEmpty else { return }
            self.findNeedle = text
            self.startFind()
            self.find()
        }
    }

    func hide() {
        guard let panel = workspace?.terminalPanel(for: rootPanelID), panel.agentWorkspace === self else { return }
        releaseRenderer()
        panel.agentWorkspace = nil
        panel.recordPortalHostOwnershipChange()
        panel.focus()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let source = message.frameInfo.request.url,
              source.scheme == baseURL.scheme, source.host == baseURL.host, source.port == baseURL.port,
              source.path.hasPrefix(baseURL.path + "/"),
              let body = message.body as? [String: Any],
              let action = body["action"] as? String,
              let workspace,
              workspace.terminalPanel(for: rootPanelID)?.agentWorkspace === self else { return }
        switch action {
        case "hide": hide()
        case "dismiss-terminal": hideTerminal()
        case "selection":
            guard let selection = body["selection"] as? [String: Any],
                  selection["version"] as? Int == 1,
                  let data = try? JSONSerialization.data(withJSONObject: selection), data.count < 4096,
                  let value = String(data: data, encoding: .utf8) else { return }
            defaults.set(value, forKey: selectionKey)
        case "root-terminal", "terminal":
            let sessionID = body["sessionId"] as? String ?? rootSessionID
            let provider = body["provider"] as? String ?? rootProvider
            let surfaceID = (body["surfaceId"] as? String).flatMap(UUID.init(uuidString:)) ?? rootPanelID
            // Check the live registry again at click time. A stale page cannot
            // focus a replacement agent or a surface that moved workspaces.
            guard hasCurrentSessionBindings(panelID: surfaceID, sessionID: sessionID, provider: provider),
                  let panel = workspace.terminalPanel(for: surfaceID),
                  panel.workspaceId == workspace.id else { NSSound.beep(); return }
            if !showTerminal(panel: panel, sessionID: sessionID, provider: provider) {
                workspace.focusPanel(surfaceID)
            }
        default: break
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let local = url.scheme == baseURL.scheme && url.host == baseURL.host && url.port == baseURL.port
            && (url.path == baseURL.path || url.path.hasPrefix(baseURL.path + "/"))
        if local { decisionHandler(.allow) }
        else {
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated, ["https", "http"].contains(url.scheme ?? "") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
