import WebKit

/// WKUserContentController retains its handler; keep the presentation weak.
@MainActor
final class AgentWorkspaceMessageProxy: NSObject, WKScriptMessageHandler {
    private weak var target: AgentWorkspacePresentation?

    init(_ target: AgentWorkspacePresentation) { self.target = target }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
