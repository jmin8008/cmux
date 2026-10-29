import SwiftUI
import CmuxBrowser

/// The group chat stays visible above the selected existing terminal.
struct AgentWorkspacePanelView<TerminalContent: View>: View {
    @Bindable var presentation: AgentWorkspacePresentation
    @FocusState private var findFocused: Bool
    let isVisible: Bool
    @ViewBuilder let terminal: () -> TerminalContent

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    presentation.hide()
                } label: {
                    Label(String(localized: "agentWorkspace.returnToTerminal", defaultValue: "Return to terminal"), systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(8)
            if presentation.showsFind {
                HStack {
                    TextField(String(localized: "menu.find.find", defaultValue: "Find…"), text: $presentation.findNeedle)
                        .focused($findFocused)
                        .onSubmit { presentation.find() }
                        .onAppear { findFocused = true }
                    Button { presentation.find(backwards: true) } label: { Image(systemName: "chevron.up") }
                        .accessibilityLabel(String(localized: "menu.find.findPrevious", defaultValue: "Find Previous"))
                    Button { presentation.find() } label: { Image(systemName: "chevron.down") }
                        .accessibilityLabel(String(localized: "menu.find.findNext", defaultValue: "Find Next"))
                    Button { presentation.hideFind() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(String(localized: "agentWorkspace.hideFind", defaultValue: "Hide search"))
                }
                .padding(8)
            }
            if isVisible {
                AgentWorkspaceWebView(presentation: presentation)
                    .frame(minHeight: 180, maxHeight: .infinity)
                    .onAppear { presentation.focus() }
            }
            if presentation.showsTerminal {
                HStack {
                    Text(String(localized: "agentWorkspace.originalTerminal", defaultValue: "Original terminal"))
                    Spacer()
                    Button {
                        presentation.hideTerminal()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "agentWorkspace.hideTerminal", defaultValue: "Hide terminal"))
                }
                .padding(8)
                Divider()
                terminal().frame(minHeight: 140, maxHeight: .infinity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: CmuxWebView.didBecomeFirstResponderNotification)) { notification in
            guard isVisible, (notification.object as? CmuxWebView) === presentation.webView else { return }
            presentation.webContentDidBecomeFocused()
        }
        .onChange(of: isVisible) { _, visible in
            if !visible { presentation.releaseRenderer() }
        }
    }
}
