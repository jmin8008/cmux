import Foundation

/// Formats selected page content as quoted data for literal terminal paste.
public struct BrowserContextFormatter: Sendable {
    /// The maximum accepted capture or formatted prompt size in UTF-8 bytes.
    public static let maximumBytes = 32_768

    /// Creates a text-only formatter.
    public init() {}

    /// Formats one bounded selection, removing terminal controls and URL secrets.
    /// - Parameter capture: The current document's selection.
    /// - Returns: A bracketed context block, or nil for invalid or oversized data.
    public func format(_ capture: BrowserContextCapture) -> String? {
        guard ["element", "text"].contains(capture.kind),
              [capture.text, capture.selector, capture.url, capture.tag].allSatisfy({ $0.utf8.count <= Self.maximumBytes }),
              let source = sanitizedURL(capture.url) else { return nil }
        let b = capture.bounds
        let v = capture.viewport
        guard [b.x, b.y, b.width, b.height, v.width, v.height, v.scrollX, v.scrollY].allSatisfy(\.isFinite),
              b.width >= 0, b.height >= 0, v.width > 0, v.height > 0 else { return nil }
        // Field names are invariant interchange identifiers; all page strings are JSON-quoted data.
        let payload: [String: Any] = [
            "url": clean(source), "selection": capture.kind, "text": clean(capture.text),
            "element_tag": clean(capture.tag), "css_selector": clean(capture.selector),
            "bounds_viewport_css_px": ["x": b.x, "y": b.y, "width": b.width, "height": b.height],
            "viewport_css_px": ["width": v.width, "height": v.height],
            "scroll_css_px": ["x": v.scrollX, "y": v.scrollY],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let json = String(data: data, encoding: .utf8) else { return nil }
        let heading = String(localized: "browser.context.envelope", defaultValue: "Web context (quoted page data)")
        let result = "[\(heading)\n\(json)\n]"
        return result.utf8.count <= Self.maximumBytes ? result : nil
    }

    private func clean(_ value: String) -> String {
        let bidiControls = CharacterSet(charactersIn: "\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}")
        return String(value.unicodeScalars.filter {
            (!CharacterSet.controlCharacters.contains($0) && !bidiControls.contains($0)) || $0 == "\n" || $0 == "\t"
        })
    }

    private func sanitizedURL(_ raw: String) -> String? {
        guard var parts = URLComponents(string: raw),
              let scheme = parts.scheme?.lowercased(), ["http", "https", "file"].contains(scheme) else { return nil }
        parts.user = nil
        parts.password = nil
        // Queries and hash routes may contain credentials, even without recognizable key names.
        parts.query = nil
        parts.fragment = nil
        return parts.string
    }
}
