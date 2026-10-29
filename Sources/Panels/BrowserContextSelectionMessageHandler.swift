import Foundation
import WebKit

/// The isolated content-world boundary never accepts a page-supplied destination.
@MainActor
final class BrowserContextSelectionMessageHandler: NSObject, WKScriptMessageHandler {
    let receive: @MainActor ([String: Any]) -> Void

    init(receive: @escaping @MainActor ([String: Any]) -> Void) {
        self.receive = receive
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any] else { return }
        receive(body)
    }
}
