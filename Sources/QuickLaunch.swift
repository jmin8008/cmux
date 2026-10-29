import AppKit
import CmuxSettings
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class QuickLaunchModel: ObservableObject {
    static let shared = QuickLaunchModel()
    private let store = JSONConfigStore(fileURL: CmuxConfigLocation().userConfigFile)
    @Published private(set) var entries: [QuickLaunchEntry] = []
    @Published private(set) var readOnly = true
    @Published var error: String?
    @Published private(set) var opening: Set<UUID> = []
    private var observation: Task<Void, Never>?
    private var bindings: [UUID: [UUID: UUID]] = [:]
    private static var configurationError: String {
        String(localized: "quickLaunch.error.config", defaultValue: "The shortcuts configuration is unreadable or uses a newer format. Fix the configuration file before editing.")
    }

    private init() {
        observation = Task { [weak self, store] in
            for await state in store.quickLaunchStates() {
                guard let self else { return }
                switch state {
                case let .ready(registry):
                    entries = registry.entries
                    readOnly = false
                    if error == Self.configurationError { error = nil }
                case .unreadable:
                    readOnly = true
                    error = Self.configurationError
                }
            }
        }
    }

    func mutate(_ mutation: QuickLaunchMutation) async -> Bool {
        do {
            try await store.applyQuickLaunch(mutation)
            if case let .ready(registry) = await store.quickLaunchState() { entries = registry.entries }
            error = nil
            return true
        } catch {
            self.error = String(localized: "quickLaunch.error.save", defaultValue: "Could not save the shortcut. The configuration may have changed; reopen the editor and try again.")
            return false
        }
    }

    func open(_ entry: QuickLaunchEntry, in window: NSWindow?) async {
        guard !opening.contains(entry.id), !readOnly else { return }
        opening.insert(entry.id)
        defer { opening.remove(entry.id) }
        do {
            try entry.validate()
            switch entry.target.kind {
            case .app:
                try await openApp(entry)
            case .web:
                guard let url = QuickLaunchEntry.webURL(entry.target.url) else { throw QuickLaunchError.invalidEntry }
                if entry.openMode == .systemBrowser {
                    guard NSWorkspace.shared.open(url) else { throw QuickLaunchError.invalidEntry }
                } else {
                    guard let window,
                          let workspace = AppDelegate.shared?.contextForMainTerminalWindow(window)?.tabManager.selectedWorkspace,
                          !workspace.isRemoteWorkspace, workspace.cloudVMBinding == nil,
                          let pane = workspace.bonsplitController.focusedPaneId ?? workspace.bonsplitController.allPaneIds.first else {
                        throw QuickLaunchError.invalidEntry
                    }
                    let profile = workspace.quickLaunchProfileID()
                    let candidates = workspace.panels.values.compactMap { $0 as? BrowserPanel }.map {
                        QuickLaunchBrowserCandidate(panelID: $0.id, workspaceID: workspace.id,
                            profileID: $0.profileID, url: $0.currentURL?.absoluteString)
                    }
                    let match = QuickLaunchBrowserReuse.panelID(for: url.absoluteString, workspaceID: workspace.id,
                        profileID: profile, boundPanelID: bindings[workspace.id]?[entry.id],
                        focusedPanelID: workspace.focusedPanelId, candidates: candidates)
                    if let match {
                        workspace.focusPanel(match)
                        bindings[workspace.id, default: [:]][entry.id] = match
                    } else if let panel = workspace.newBrowserSurface(
                        inPane: pane,
                        url: url,
                        focus: true,
                        preferredProfileID: profile,
                        allowsExternalBrowserFallback: false,
                        bypassRemoteProxy: true
                    ) {
                        bindings[workspace.id, default: [:]][entry.id] = panel.id
                    } else {
                        throw QuickLaunchError.invalidEntry
                    }
                }
            }
            error = nil
        } catch {
            self.error = entry.target.kind == .app
                ? String(localized: "quickLaunch.error.app", defaultValue: "This app could not be opened. Edit the shortcut and select the installed app again.")
                : String(localized: "quickLaunch.error.open", defaultValue: "This shortcut could not be opened in this workspace. Check the address and browser availability.")
        }
    }

    private func openApp(_ entry: QuickLaunchEntry) async throws {
        guard let storedURL = URL(string: entry.target.url),
              let bundleID = entry.target.bundleIdentifier else { throw QuickLaunchError.invalidEntry }
        var url = storedURL
        if let bookmark = entry.target.bookmark {
            var stale = false
            url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale)
            guard !stale, url.standardizedFileURL == storedURL.standardizedFileURL else { throw QuickLaunchError.invalidEntry }
        }
        guard FileManager.default.fileExists(atPath: url.path),
              Bundle(url: url)?.bundleIdentifier == bundleID else { throw QuickLaunchError.invalidEntry }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: {
            $0.bundleURL?.standardizedFileURL == url.standardizedFileURL
        }) {
            guard running.activate() else { throw QuickLaunchError.invalidEntry }
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}

@MainActor
final class QuickLaunchPresenter {
    static let shared = QuickLaunchPresenter()
    private var popover: NSPopover?

    func show(anchor: NSView, at point: NSPoint? = nil) {
        if let popover, popover.isShown { popover.close(); self.popover = nil; return }
        guard let window = anchor.window else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: QuickLaunchList(window: window))
        popover.contentSize = NSSize(width: 360, height: 400)
        self.popover = popover
        let rect = point.map { NSRect(origin: $0, size: NSSize(width: 1, height: 1)) } ?? anchor.bounds
        popover.show(relativeTo: rect, of: anchor, preferredEdge: .maxY)
    }
}

struct QuickLaunchAnchorView: NSViewRepresentable {
    let onResolve: (NSView) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        onResolve(view)
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { onResolve(view) }
}

private struct QuickLaunchList: View {
    @ObservedObject private var model = QuickLaunchModel.shared
    weak var window: NSWindow?
    @State private var editor: QuickLaunchDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "quickLaunch.title", defaultValue: "Quick Launch")).font(.headline)
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if model.entries.isEmpty && !model.readOnly {
                Text(String(localized: "quickLaunch.empty", defaultValue: "Add apps and websites you use often.")).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.entries) { entry in
                        Button {
                            Task { await model.open(entry, in: window) }
                        } label: {
                            HStack {
                                Image(systemName: entry.symbol).frame(width: 20)
                                Text(entry.name).lineLimit(1)
                                Spacer()
                                if model.opening.contains(entry.id) { ProgressView().controlSize(.small) }
                            }
                            .padding(8).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(model.readOnly || model.opening.contains(entry.id))
                        .contextMenu {
                            Button(String(localized: "common.edit", defaultValue: "Edit")) { editor = QuickLaunchDraft(entry: entry) }
                            Button(String(localized: "quickLaunch.moveUp", defaultValue: "Move Up")) { move(entry, offset: -1) }
                            Button(String(localized: "quickLaunch.moveDown", defaultValue: "Move Down")) { move(entry, offset: 1) }
                            Button(String(localized: "common.delete", defaultValue: "Delete"), role: .destructive) {
                                Task { _ = await model.mutate(.remove(entry)) }
                            }
                        }
                        .draggable(entry.id.uuidString)
                        .dropDestination(for: String.self) { items, _ in
                            guard !model.readOnly, let value = items.first, let id = UUID(uuidString: value),
                                  model.entries.contains(where: { $0.id == id }) else { return false }
                            Task { _ = await model.mutate(.move(id, before: entry.id)) }
                            return true
                        }
                    }
                }
            }
            Divider()
            Button { editor = QuickLaunchDraft() } label: {
                Label(String(localized: "quickLaunch.add", defaultValue: "Add Shortcut"), systemImage: "plus")
            }
            .disabled(model.readOnly)
        }
        .padding(16).frame(width: 360, height: 400)
        .sheet(item: $editor) { draft in QuickLaunchEditor(draft: draft, window: window) }
    }

    private func move(_ entry: QuickLaunchEntry, offset: Int) {
        guard let index = model.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let destination = index + offset
        guard model.entries.indices.contains(destination) else { return }
        let before = offset < 0 ? model.entries[destination].id : model.entries.dropFirst(destination + 1).first?.id
        Task { _ = await model.mutate(.move(entry.id, before: before)) }
    }
}

private struct QuickLaunchDraft: Identifiable {
    var id: UUID
    var original: QuickLaunchEntry?
    var name: String
    var kind: QuickLaunchEntry.Kind
    var url: String
    var openMode: QuickLaunchEntry.OpenMode
    var symbol: String
    var appTarget: QuickLaunchEntry.Target?

    init(entry: QuickLaunchEntry? = nil) {
        id = entry?.id ?? UUID()
        original = entry
        name = entry?.name ?? ""
        kind = entry?.target.kind ?? .web
        url = entry?.target.kind == .web ? entry!.target.url : ""
        openMode = entry?.openMode ?? .inApp
        symbol = entry?.symbol ?? "globe"
        appTarget = entry?.target.kind == .app ? entry?.target : nil
    }
}

private struct QuickLaunchEditor: View {
    @State var draft: QuickLaunchDraft
    weak var window: NSWindow?
    @ObservedObject private var model = QuickLaunchModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "quickLaunch.editor", defaultValue: "Shortcut")).font(.headline)
            Form {
                TextField(String(localized: "quickLaunch.name", defaultValue: "Name"), text: $draft.name)
                Picker(String(localized: "quickLaunch.kind", defaultValue: "Target"), selection: $draft.kind) {
                    Text(String(localized: "quickLaunch.web", defaultValue: "Website")).tag(QuickLaunchEntry.Kind.web)
                    Text(String(localized: "quickLaunch.app", defaultValue: "Application")).tag(QuickLaunchEntry.Kind.app)
                }
                if draft.kind == .web {
                    TextField(String(localized: "quickLaunch.address", defaultValue: "Web Address"), text: $draft.url).textFieldStyle(.roundedBorder)
                    Button(String(localized: "quickLaunch.currentPage", defaultValue: "Use Current Page")) { useCurrentPage() }
                    Picker(String(localized: "quickLaunch.openIn", defaultValue: "Open In"), selection: $draft.openMode) {
                        Text(String(localized: "quickLaunch.inApp", defaultValue: "cmux Browser")).tag(QuickLaunchEntry.OpenMode.inApp)
                        Text(String(localized: "quickLaunch.systemBrowser", defaultValue: "Default Browser")).tag(QuickLaunchEntry.OpenMode.systemBrowser)
                    }
                } else {
                    Text(draft.appTarget.flatMap { URL(string: $0.url)?.path } ?? String(localized: "quickLaunch.chooseAppHint", defaultValue: "Select an installed application."))
                        .font(.caption).lineLimit(2).textSelection(.enabled)
                    Button(String(localized: "quickLaunch.chooseApp", defaultValue: "Choose App…")) { chooseApp() }
                }
                Picker(String(localized: "quickLaunch.icon", defaultValue: "Icon"), selection: $draft.symbol) {
                    ForEach(QuickLaunchEntry.symbols, id: \.self) { symbol in Image(systemName: symbol).tag(symbol) }
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(String(localized: "common.cancel", defaultValue: "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(String(localized: "common.save", defaultValue: "Save")) { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 430).disabled(saving)
        .onChange(of: draft.kind) { _, kind in
            draft.openMode = kind == .app ? .native : .inApp
            draft.symbol = kind == .app ? "app" : "globe"
        }
    }

    private func useCurrentPage() {
        guard let window, let workspace = AppDelegate.shared?.contextForMainTerminalWindow(window)?.tabManager.selectedWorkspace,
              let id = workspace.focusedPanelId, let panel = workspace.panels[id] as? BrowserPanel,
              let url = panel.currentURL, QuickLaunchEntry.webURL(url.absoluteString) != nil else { return }
        draft.url = url.absoluteString
        if draft.name.isEmpty { draft.name = panel.displayTitle }
    }

    private func chooseApp() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.applicationBundle]
        picker.allowsMultipleSelection = false
        picker.canChooseDirectories = false
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        guard picker.runModal() == .OK, let url = picker.url,
              let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { return }
        draft.appTarget = .init(kind: .app, url: url.absoluteString, bundleIdentifier: identifier,
            bookmark: try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
        if draft.name.isEmpty { draft.name = url.deletingPathExtension().lastPathComponent }
    }

    private func save() {
        let target: QuickLaunchEntry.Target
        if draft.kind == .web { target = .init(kind: .web, url: draft.url.trimmingCharacters(in: .whitespacesAndNewlines)) }
        else if let selected = draft.appTarget { target = selected }
        else { error = String(localized: "quickLaunch.chooseAppHint", defaultValue: "Select an installed application."); return }
        let entry = QuickLaunchEntry(id: draft.id, name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            target: target, openMode: draft.kind == .app ? .native : draft.openMode, symbol: draft.symbol)
        do { try entry.validate() }
        catch { self.error = String(localized: "quickLaunch.error.input", defaultValue: "Enter a name and an http:// or https:// address without embedded credentials."); return }
        saving = true
        Task {
            if await model.mutate(.save(entry, replacing: draft.original)) { dismiss() }
            else { error = model.error }
            saving = false
        }
    }
}
