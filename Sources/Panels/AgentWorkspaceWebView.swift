import SwiftUI
import WebKit

/// Inline WebKit host; hiding this view does not dispose the terminal session.
struct AgentWorkspaceWebView: NSViewRepresentable {
    let presentation: AgentWorkspacePresentation

    func makeNSView(context: Context) -> WKWebView { presentation.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
