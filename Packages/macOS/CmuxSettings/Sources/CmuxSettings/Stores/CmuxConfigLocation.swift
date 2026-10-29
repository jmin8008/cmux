import Foundation

/// On-disk settings locations, isolated by the development app's bundle identity.
///
/// A small value-typed bundle of URLs. Construct one with an explicit `home`
/// directory and inject it into the parts of the app that need to know where
/// the config file lives. No shared singletons; tests use a custom `home` URL
/// pointing into a temp directory.
///
/// ```swift
/// let locations = CmuxConfigLocation()
/// let store = JSONConfigStore(fileURL: locations.userConfigFile)
/// ```
public struct CmuxConfigLocation: Sendable, Hashable {
    /// The directory for JSON settings, Dock configuration and custom sidebars.
    public let directory: URL

    /// Whether this identity uses development settings instead of release settings.
    public let isDevelopment: Bool

    /// The primary cmux config file in ``directory``.
    public let userConfigFile: URL

    /// The legacy `settings.json` fallback within the same settings directory.
    public let legacyFallbackFile: URL

    /// The legacy Application Support fallback; absent for development builds.
    public let legacyApplicationSupportFile: URL?

    /// The primary path with the home directory displayed as `~`.
    public let userConfigDisplayPath: String

    /// The legacy path with the home directory displayed as `~`.
    public let legacyFallbackDisplayPath: String

    /// Creates locations for the app or its CLI without reading or copying settings.
    ///
    /// Tagged apps use `<home>/.config/cmux-dev/<bundle-suffix>/`; stable builds
    /// retain `<home>/.config/cmux/`. The native bundle identity takes precedence
    /// over inherited terminal context. The standalone CLI uses `CMUX_BUNDLE_ID`,
    /// which tagged terminals and `cmux-debug-cli.sh` already supply.
    ///
    /// - Parameters:
    ///   - home: The account home, or a temporary directory for tests.
    ///   - bundleIdentifier: The native app identity, if running inside a bundle.
    ///   - environment: CLI context when no native bundle identity is available.
    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        let identity = bundleIdentifier ?? environment["CMUX_BUNDLE_ID"] ?? "com.cmuxterm.app"
        let debugIdentity = "com.cmuxterm.app.debug"
        self.isDevelopment = identity == debugIdentity || identity.hasPrefix(debugIdentity + ".")
        let relativeDirectory: String
        if isDevelopment {
            let suffix = String(identity.dropFirst(debugIdentity.count)).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            // Never let a malformed inherited identity escape the development root.
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
            let safeSuffix = suffix.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
            let tag = safeSuffix.isEmpty || safeSuffix == "." || safeSuffix == ".." ? "untagged" : safeSuffix
            relativeDirectory = ".config/cmux-dev/\(tag)"
        } else {
            relativeDirectory = ".config/cmux"
        }
        self.directory = home.appendingPathComponent(relativeDirectory, isDirectory: true)
        self.userConfigFile = directory.appendingPathComponent("cmux.json")
        self.legacyFallbackFile = directory.appendingPathComponent("settings.json")
        self.legacyApplicationSupportFile = isDevelopment ? nil
            : home.appendingPathComponent("Library/Application Support/com.cmuxterm.app/settings.json")
        self.userConfigDisplayPath = "~/\(relativeDirectory)/cmux.json"
        self.legacyFallbackDisplayPath = "~/\(relativeDirectory)/settings.json"
    }
}
