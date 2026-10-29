import AppKit
import CmuxBrowser
import Observation
import WebKit

/// Owns the browser revision and fixed destination of text-only selection.
@MainActor
@Observable
final class BrowserContextSelectionController {
    static let world = WKContentWorld.world(name: "cmuxContextSelection")
    static let handlerName = "cmuxContextSelection"
    private(set) var isActive = false
    private(set) var isTransitioning = false
    private(set) var target: BrowserContextTarget?
    private(set) var candidates: [BrowserContextTarget] = []
    private(set) var message: String?
    private(set) var lastContext: String?
    var isTargetPickerPresented = false
    @ObservationIgnored private weak var webView: WKWebView?
    @ObservationIgnored private var handler: BrowserContextSelectionMessageHandler?
    @ObservationIgnored private var gate = BrowserContextDeliveryGate()
    @ObservationIgnored private var selection = BrowserContextTargetSelection()
    @ObservationIgnored private var operation = UUID()
    @ObservationIgnored private var pageURL: URL?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let targets: @MainActor () -> [BrowserContextTarget]
    @ObservationIgnored private let paste: @MainActor (String, UUID) -> Bool
    @ObservationIgnored private let prepare: @MainActor () async -> Bool
    @ObservationIgnored private let activityChanged: @MainActor () -> Void

    init(targets: @escaping @MainActor () -> [BrowserContextTarget],
         paste: @escaping @MainActor (String, UUID) -> Bool,
         prepare: @escaping @MainActor () async -> Bool,
         activityChanged: @escaping @MainActor () -> Void) {
        self.targets = targets
        self.paste = paste
        self.prepare = prepare
        self.activityChanged = activityChanged
    }

    func install(on webView: WKWebView) {
        if let old = self.webView, old !== webView { remove(from: old) }
        self.webView = webView
        let handler = BrowserContextSelectionMessageHandler { [weak self] body in self?.receive(body) }
        self.handler = handler
        let content = webView.configuration.userContentController
        content.removeScriptMessageHandler(forName: Self.handlerName, contentWorld: Self.world)
        content.add(handler, contentWorld: Self.world, name: Self.handlerName)
    }

    func refreshTargets() {
        candidates = targets().filter(\.isAgent)
    }

    func toggle() {
        if isActive || isTransitioning { stop(); return }
        refreshTargets()
        // Automatic targets are re-resolved from current input recency on every
        // activation; only an explicit user choice is remembered.
        target = selection.resolve(candidates)
        guard target != nil else {
            message = String(localized: "browser.context.chooseTarget", defaultValue: "Choose an agent terminal for selected context.")
            isTargetPickerPresented = true
            return
        }
        start()
    }

    func selectTarget(_ target: BrowserContextTarget) {
        stop()
        selection.choose(target.id)
        self.target = target
        isTargetPickerPresented = false
        start()
    }

    private func start() {
        guard let target, let webView, let url = webView.url else {
            presentUnavailable()
            return
        }
        let revision = UUID()
        operation = revision
        isTransitioning = true
        activityChanged()
        message = nil
        task = Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            guard await self.prepare(), self.operation == revision, !Task.isCancelled else {
                if self.operation == revision {
                    self.isTransitioning = false
                    self.presentUnavailable()
                }
                return
            }
            do {
                let script = try BrowserContextSelectionScript().source()
                guard self.operation == revision, webView.url == url else { return }
                let activated = try await self.activateRuntime(
                    script + "\nwindow.__cmuxContextPicker.start('\(revision.uuidString)')",
                    in: webView
                )
                guard self.operation == revision, !Task.isCancelled, webView.url == url else { return }
                guard activated else { throw CocoaError(.featureUnsupported) }
                // The pinned terminal may have closed or moved while the runtime was installing.
                self.refreshTargets()
                guard self.candidates.contains(where: { $0.id == target.id }) else {
                    self.stop()
                    self.message = String(localized: "browser.context.targetGone", defaultValue: "The agent terminal is no longer available in this workspace. Choose a target or copy the context.")
                    self.isTargetPickerPresented = true
                    return
                }
                self.pageURL = url
                self.gate.arm(targetID: target.id, revision: revision)
                self.isActive = true
                self.isTransitioning = false
                self.activityChanged()
            } catch {
                guard self.operation == revision else { return }
                self.stop()
                self.presentUnavailable()
            }
        }
    }

    private func activateRuntime(_ source: String, in webView: WKWebView) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(source, in: nil, in: Self.world) { result in
                continuation.resume(with: result.map { $0 as? Bool == true })
            }
        }
    }

    func stop() {
        operation = UUID()
        task?.cancel()
        task = nil
        gate.invalidate()
        isActive = false
        isTransitioning = false
        pageURL = nil
        if let webView {
            webView.evaluateJavaScript("window.__cmuxContextPicker?.stop()", in: nil, in: Self.world) { _ in }
        }
        activityChanged()
    }

    func documentChanged(to url: URL?) {
        if (isActive || isTransitioning), url != pageURL { stop() }
    }

    func remove(from webView: WKWebView) {
        stop()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.handlerName, contentWorld: Self.world)
        if self.webView === webView { self.webView = nil }
        handler = nil
        lastContext = nil
    }

    func copyLastContext() {
        guard let lastContext else { return }
        _ = GhosttyApp.terminalPasteboard.writeString(lastContext, to: .general)
    }

    private func receive(_ body: [String: Any]) {
        guard isActive else { return }
        if body["type"] as? String == "exit", body["revision"] as? String == gate.revision?.uuidString { stop(); return }
        if body["type"] as? String == "too_large", body["revision"] as? String == gate.revision?.uuidString {
            rejectCapture(); return
        }
        guard body["type"] as? String == "capture", let object = body["capture"],
              JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        guard data.count <= BrowserContextFormatter.maximumBytes,
              let capture = try? JSONDecoder().decode(BrowserContextCapture.self, from: data),
              let prompt = BrowserContextFormatter().format(capture) else { rejectCapture(); return }
        guard capture.revision == gate.revision, URL(string: capture.url) == pageURL, webView?.url == pageURL else { return }
        lastContext = prompt
        refreshTargets()
        guard let targetID = gate.targetID, candidates.contains(where: { $0.id == targetID }) else {
            stop()
            message = String(localized: "browser.context.targetGone", defaultValue: "The agent terminal is no longer available in this workspace. Choose a target or copy the context.")
            isTargetPickerPresented = true
            return
        }
        guard let claimed = gate.claim(capture, availableTargetIDs: Set(candidates.map(\.id))) else { return }
        if paste(prompt, claimed) {
            message = String(localized: "browser.context.inserted", defaultValue: "Context inserted. Add your request in the terminal, then press Enter.")
        } else {
            message = String(localized: "browser.context.pasteFailed", defaultValue: "Context could not be inserted. Copy it or make a new selection; it will not be retried automatically.")
            isTargetPickerPresented = true
        }
    }

    private func presentUnavailable() {
        message = String(localized: "browser.context.unavailable", defaultValue: "Context selection is available on HTML pages. Reload the page and try again.")
        isTargetPickerPresented = true
    }

    private func rejectCapture() {
        message = String(localized: "browser.context.tooLarge", defaultValue: "This selection is invalid or exceeds 32 KB. Select a smaller visible element or text.")
        isTargetPickerPresented = true
    }
}
