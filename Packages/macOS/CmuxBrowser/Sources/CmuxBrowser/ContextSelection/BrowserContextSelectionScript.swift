import Foundation

/// Loads the isolated, text-only context picker shipped with the browser package.
public struct BrowserContextSelectionScript: Sendable {
    /// Creates the bundled picker loader.
    public init() {}

    /// Loads the context picker JavaScript.
    /// - Returns: Source for evaluation in an isolated WebKit content world.
    /// - Throws: A Cocoa file error when the resource is missing or unreadable.
    public func source() throws -> String {
        let bundleName = "CmuxBrowser_CmuxBrowser.bundle"
        let roots = [Bundle.main.resourceURL, Bundle.main.bundleURL, Bundle(for: BrowserContextSelectionBundleFinder.self).resourceURL,
                     Bundle.main.bundleURL.deletingLastPathComponent(), Bundle(for: BrowserContextSelectionBundleFinder.self).bundleURL.deletingLastPathComponent()]
        for root in roots.compactMap({ $0 }) {
            guard let bundle = Bundle(url: root.appendingPathComponent(bundleName)),
                  let url = bundle.url(forResource: "BrowserContextSelectionRuntime", withExtension: "js") else { continue }
            return try String(contentsOf: url, encoding: .utf8)
        }
        throw CocoaError(.fileNoSuchFile)
    }
}

