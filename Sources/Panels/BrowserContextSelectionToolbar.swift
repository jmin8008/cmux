import SwiftUI

/// Keeps the selected destination visible while the picker is armed.
struct BrowserContextSelectionToolbar: View {
    let controller: BrowserContextSelectionController
    let hitSize: CGFloat

    var body: some View {
        HStack(spacing: 2) {
            Button { controller.toggle() } label: {
                Image(systemName: controller.isActive ? "scope" : "cursorarrow.click.2")
                    .foregroundStyle(controller.isActive ? Color.accentColor : Color.secondary)
                    .frame(width: hitSize, height: hitSize)
            }
            .buttonStyle(OmnibarAddressButtonStyle())
            .safeHelp(String(localized: "browser.context.toggle", defaultValue: "Select context for agent terminal"))
            .accessibilityLabel(String(localized: "browser.context.toggle", defaultValue: "Select context for agent terminal"))
            .accessibilityIdentifier("BrowserContextSelectionToggle")
            if controller.isActive || controller.isTransitioning {
                Button {
                    controller.refreshTargets()
                    controller.isTargetPickerPresented = true
                } label: {
                    HStack(spacing: 3) {
                        Text(controller.target?.title ?? "").lineLimit(1).frame(maxWidth: 110)
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .safeHelp(controller.message ?? String(localized: "browser.context.target", defaultValue: "Context destination"))
                .accessibilityIdentifier("BrowserContextSelectionTarget")
            }
        }
        .popover(isPresented: Binding(get: { controller.isTargetPickerPresented }, set: { controller.isTargetPickerPresented = $0 })) {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "browser.context.target", defaultValue: "Context destination")).font(.headline)
                Text(controller.message ?? String(localized: "browser.context.instructions", defaultValue: "Click an element or drag to select text. Context is pasted without pressing Enter."))
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                if controller.candidates.isEmpty {
                    Text(String(localized: "browser.context.noAgents", defaultValue: "No agent terminal was detected in this workspace. Start an agent here, then try again."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(controller.candidates) { target in
                    Button { controller.selectTarget(target) } label: {
                        HStack {
                            Image(systemName: target.id == controller.target?.id ? "checkmark.circle.fill" : "terminal")
                            Text(target.title)
                            Spacer()
                            Text(String(target.id.uuidString.prefix(6))).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if controller.lastContext != nil {
                    Button(String(localized: "browser.context.copy", defaultValue: "Copy last context")) { controller.copyLastContext() }
                }
            }
            .padding(16)
            .frame(width: 340)
            .onAppear { controller.refreshTargets() }
        }
    }
}
