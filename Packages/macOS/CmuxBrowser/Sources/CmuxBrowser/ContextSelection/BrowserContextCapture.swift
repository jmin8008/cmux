public import Foundation

/// A bounded, text-only selection captured in one browser document revision.
public struct BrowserContextCapture: Decodable, Sendable {
    /// Identifies this mouse gesture for duplicate suppression.
    public let id: UUID
    /// The app-owned revision installed when selection was armed.
    public let revision: UUID
    /// The source document URL at mouse-up.
    public let url: String
    /// Either `element` or `text`; no pixel or region payload is accepted.
    public let kind: String
    /// Visible selected text, or a clicked image's alt text.
    public let text: String
    /// A best-effort CSS selector, never a source-code location.
    public let selector: String
    /// The selected HTML tag name.
    public let tag: String
    /// Viewport-relative CSS pixel bounds.
    public let bounds: BrowserDesignModeRect
    /// CSS viewport dimensions and scroll position at capture time.
    public let viewport: BrowserDesignModeViewport
}
