import AppKit
import Bonsplit
import CmuxMobileHost
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite("Agent workspace renderer lease", .serialized)
struct AgentWorkspaceRendererLeaseTests {
    private func record(_ sessionID: String, panel: TerminalPanel, workspace: Workspace) -> AgentChatSessionRecord {
        AgentChatSessionRecord(sessionID: sessionID, agentKind: .claude, workspaceID: workspace.id.uuidString,
            surfaceID: panel.id.uuidString, workingDirectory: nil, transcriptPath: nil, state: .idle,
            lastActivityAt: Date(), title: nil, pid: nil)
    }

    private func makeGroup(_ workspace: Workspace, root: TerminalPanel, member: TerminalPanel? = nil,
                           memberSessionID: String = "member", service: AgentChatTranscriptService? = nil) -> AgentWorkspacePresentation {
        let records = [record("root-session", panel: root, workspace: workspace)]
            + (member.map { [record(memberSessionID, panel: $0, workspace: workspace)] } ?? [])
        let sessionService = service ?? AgentChatTranscriptService(registry: AgentChatSessionRegistry(restoredRecords: records),
            hasEventSubscribers: { false }, emitEventPayload: { _ in })
        let presentation = AgentWorkspacePresentation(
            workspace: workspace,
            rootPanelID: root.id,
            rootSessionID: "root-session",
            rootProvider: "claude",
            url: URL(string: "http://127.0.0.1:1/token/terminal/\(root.id.uuidString)")!,
            sessionService: sessionService
        )
        root.agentWorkspace = presentation
        workspace.focusPanel(root.id)
        return presentation
    }

    @Test func switchingMembersPreservesSessionsAndRevokesOldHostEligibility() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let root = try #require(workspace.focusedTerminalPanel)
        let pane = try #require(workspace.paneId(forPanelId: root.id))
        let member = try #require(workspace.newTerminalSurface(inPane: pane, focus: false))
        let rootSurface = root.surface, memberSurface = member.surface
        let panelIDs = Set(workspace.panels.keys)
        let group = makeGroup(workspace, root: root, member: member, memberSessionID: "member-session")
        defer { group.sessionService?.shutdown() }
        #expect(group.showTerminal(panel: member, sessionID: "member-session", provider: "claude"))
        let oldLease = try #require(group.rendererLease)
        #expect(oldLease.isCurrent)
        #expect(oldLease.ownsPortal(in: pane))
        #expect(member.agentWorkspaceRendererLease === oldLease)
        #expect(!member.allowsCanonicalAgentWorkspaceRenderer)
        #expect(workspace.focusedTerminalInputTarget()?.panel === member)
        #expect(workspace.terminalInputTarget(forPanelID: root.id)?.panel === root)
        workspace.reconcileTerminalPortalVisibilityForCurrentRenderedLayout()
        #expect(member.hostedView.debugPortalVisibleInUI)
        #expect(!root.hostedView.debugPortalVisibleInUI)

        #expect(group.showTerminal(panel: root, sessionID: "root-session", provider: "claude"))
        #expect(!oldLease.isCurrent)
        #expect(!oldLease.ownsPortal(in: pane))
        #expect(member.agentWorkspaceRendererLease == nil)
        #expect(member.allowsCanonicalAgentWorkspaceRenderer)
        #expect(group.selectedTerminalPanel === root)
        group.hideTerminal()
        #expect(group.selectedTerminalPanel == nil)
        #expect(root.surface === rootSurface)
        #expect(member.surface === memberSurface)
        #expect(Set(workspace.panels.keys) == panelIDs)
    }

    @Test func competingGroupCannotClaimBorrowedTerminal() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let root = try #require(workspace.focusedTerminalPanel)
        let pane = try #require(workspace.paneId(forPanelId: root.id))
        let otherRoot = try #require(workspace.newTerminalSurface(inPane: pane, focus: false))
        let member = try #require(workspace.newTerminalSurface(inPane: pane, focus: false))
        let first = makeGroup(workspace, root: root, member: member)
        defer { first.sessionService?.shutdown() }
        #expect(first.showTerminal(panel: member, sessionID: "member", provider: "claude"))
        let second = makeGroup(workspace, root: otherRoot, member: member)
        defer { second.sessionService?.shutdown() }
        #expect(!second.showTerminal(panel: member, sessionID: "member", provider: "claude"))
        #expect(first.selectedTerminalPanel === member)
        #expect(second.selectedTerminalPanel == nil)
        first.releaseRenderer()
        #expect(second.showTerminal(panel: member, sessionID: "member", provider: "claude"))
    }

    @Test func workspaceHideAndMemberMoveRevokeBorrowWithoutClosingSurface() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let root = try #require(workspace.focusedTerminalPanel)
        let pane = try #require(workspace.paneId(forPanelId: root.id))
        let member = try #require(workspace.newTerminalSurface(inPane: pane, focus: false))
        let surface = member.surface
        let group = makeGroup(workspace, root: root, member: member)
        defer { group.sessionService?.shutdown() }
        #expect(group.showTerminal(panel: member, sessionID: "member", provider: "claude"))
        workspace.setPortalRenderingEnabled(false, reason: "test")
        #expect(group.rendererLease == nil)
        #expect(member.agentWorkspaceRendererLease == nil)
        workspace.setPortalRenderingEnabled(true, reason: "test")
        #expect(group.showTerminal(panel: member, sessionID: "member", provider: "claude"))
        member.updateWorkspaceId(UUID())
        #expect(group.rendererLease == nil)
        #expect(member.agentWorkspaceRendererLease == nil)
        #expect(member.surface === surface)
        #expect(surface.canAcceptPortalBinding(expectedSurfaceId: member.id, expectedGeneration: nil))
    }

    @Test func rootRemovalAndSurfaceGenerationFenceInvalidateQueuedLease() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let root = try #require(workspace.focusedTerminalPanel)
        let pane = try #require(workspace.paneId(forPanelId: root.id))
        let member = try #require(workspace.newTerminalSurface(inPane: pane, focus: false))
        let group = makeGroup(workspace, root: root, member: member)
        defer { group.sessionService?.shutdown() }
        #expect(group.showTerminal(panel: member, sessionID: "member", provider: "claude"))
        let lease = try #require(group.rendererLease)
        root.agentWorkspace = nil
        #expect(!lease.isCurrent)
        #expect(member.agentWorkspaceRendererLease == nil)
        #expect(member.allowsCanonicalAgentWorkspaceRenderer)
        root.agentWorkspace = group
        #expect(group.showTerminal(panel: member, sessionID: "member", provider: "claude"))
        let closingLease = try #require(group.rendererLease)
        member.surface.beginPortalCloseLifecycle(reason: "test")
        #expect(!closingLease.isCurrent)
        #expect(!closingLease.ownsPortal(in: pane))
    }

    @Test func staleHostDismantleCannotClearReplacementCallbacks() throws {
        let fixture = TerminalPortalTestWorkspace()
        defer { fixture.tearDown() }
        let panel = try #require(fixture.workspace.focusedTerminalPanel)
        let pane = try #require(fixture.workspace.paneId(forPanelId: panel.id))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        fixture.bind(to: window)
        defer {
            TerminalWindowPortalRegistry.detach(hostedView: panel.hostedView)
            window.close()
        }
        let oldHost = GhosttyTerminalView.HostContainerView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        let newHost = GhosttyTerminalView.HostContainerView(frame: NSRect(x: 310, y: 0, width: 300, height: 300))
        window.contentView?.addSubview(oldHost)
        window.contentView?.addSubview(newHost)
        let surface = panel.surface
        #expect(surface.claimPortalHost(hostId: ObjectIdentifier(oldHost), paneId: pane,
                                       instanceSerial: oldHost.instanceSerial, ownershipGeneration: 1,
                                       inWindow: true, bounds: oldHost.bounds, reason: "test.old"))
        TerminalWindowPortalRegistry.bind(hostedView: panel.hostedView, to: oldHost, visibleInUI: true)
        let oldCoordinator = GhosttyTerminalView.Coordinator()
        oldCoordinator.hostedView = panel.hostedView
        #expect(surface.claimPortalHost(hostId: ObjectIdentifier(newHost), paneId: pane,
                                       instanceSerial: newHost.instanceSerial, ownershipGeneration: 2,
                                       inWindow: true, bounds: newHost.bounds, reason: "test.new"))
        TerminalWindowPortalRegistry.bind(hostedView: panel.hostedView, to: newHost, visibleInUI: true)
        var focusCount = 0, flashCount = 0
        panel.hostedView.setFocusHandler { focusCount += 1 }
        panel.hostedView.setTriggerFlashHandler { flashCount += 1 }
        GhosttyTerminalView.dismantleNSView(oldHost, coordinator: oldCoordinator)
        panel.hostedView.surfaceView.onFocus?()
        panel.hostedView.surfaceView.onTriggerFlash?()
        #expect(focusCount == 1)
        #expect(flashCount == 1)
        #expect(surface.ownsPortalHost(hostId: ObjectIdentifier(newHost), instanceSerial: newHost.instanceSerial))
        #expect(TerminalWindowPortalRegistry.hasEntry(for: panel.hostedView, boundTo: newHost))
    }

    @Test(arguments: [false, true])
    func hibernatingEitherEndpointRevokesTheRenderer(hibernateRoot: Bool) throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let root = try #require(workspace.focusedTerminalPanel)
        let pane = try #require(workspace.paneId(forPanelId: root.id))
        let member = try #require(workspace.newTerminalSurface(inPane: pane, focus: false))
        let group = makeGroup(workspace, root: root, member: member)
        defer { group.sessionService?.shutdown() }
        #expect(group.showTerminal(panel: member, sessionID: "member", provider: "claude"))
        let lease = try #require(group.rendererLease)
        let endpoint = hibernateRoot ? root : member
        endpoint.agentHibernationPhase = .terminating(AgentHibernationPanelState(
            agent: SessionRestorableAgentSnapshot(kind: .claude, sessionId: "test", workingDirectory: nil, launchCommand: nil),
            hibernatedAt: Date(), lastActivityAt: Date()
        ))
        #expect(group.rendererLease == nil)
        #expect(member.agentWorkspaceRendererLease == nil)
        #expect(!lease.isCurrent)
        #expect(!group.showTerminal(panel: member, sessionID: "member", provider: "claude"))
    }

    @Test func groupFocusTracksWebAndMemberWhileExplicitSurfaceIDsStayStable() throws {
        let fixture = TerminalPortalTestWorkspace()
        defer { fixture.tearDown() }
        let workspace = fixture.workspace
        let root = try #require(workspace.focusedTerminalPanel)
        let pane = try #require(workspace.paneId(forPanelId: root.id))
        let member = try #require(workspace.newTerminalSurface(inPane: pane, focus: false))
        let group = makeGroup(workspace, root: root, member: member)
        defer { group.sessionService?.shutdown() }
        #expect(group.showTerminal(panel: member, sessionID: "member", provider: "claude"))
        #expect(workspace.agentWorkspaceFocusContainer(forSurfaceID: member.id) == root.id)
        _ = workspace.focusPanelFromTerminalInput(member.id)
        #expect(workspace.focusedPanelId == root.id)
        #expect(workspace.isFocusedTerminalInputSurface(member.id))
        #expect(workspace.terminalInputTarget(forPanelID: root.id)?.panel === root)
        #expect(workspace.terminalInputTarget(forPanelID: member.id)?.panel === member)
        #expect(workspace.controlTerminalTarget(for: root.id)?.panel === root)
        #expect(workspace.controlTerminalTarget(for: member.id)?.panel === member)
        group.webContentDidBecomeFocused()
        #expect(group.routesFindToWebContent)
        #expect(root.preferredFocusIntentForActivation() == .panel)
        workspace.reconcileTerminalPortalVisibilityForCurrentRenderedLayout()
        #expect(!member.hostedView.debugPortalActive)
        group.activateTerminal()
        #expect(!group.routesFindToWebContent)
        workspace.reconcileTerminalPortalVisibilityForCurrentRenderedLayout()
        #expect(member.hostedView.debugPortalActive)
        #expect(!root.hostedView.debugPortalActive)
    }

    @Test func foreignPanelAndStaleRootSessionCannotAcquireRenderer() throws {
        let workspace = Workspace(), otherWorkspace = Workspace()
        defer { workspace.teardownAllPanels(); otherWorkspace.teardownAllPanels() }
        let root = try #require(workspace.focusedTerminalPanel)
        let foreign = try #require(otherWorkspace.focusedTerminalPanel)
        let group = makeGroup(workspace, root: root)
        defer { group.sessionService?.shutdown() }
        #expect(!group.showTerminal(panel: foreign, sessionID: "foreign", provider: "claude"))
        #expect(!group.showTerminal(panel: root, sessionID: "replaced-session", provider: "claude"))
        #expect(!group.showTerminal(panel: root, sessionID: "root-session", provider: "codex"))
        #expect(group.rendererLease == nil)
        #expect(foreign.agentWorkspaceRendererLease == nil)
    }

    @Test(arguments: [false, true])
    func endingEitherSessionSynchronouslyReleasesInput(endsRoot: Bool) throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let root = try #require(workspace.focusedTerminalPanel)
        let pane = try #require(workspace.paneId(forPanelId: root.id))
        let member = try #require(workspace.newTerminalSurface(inPane: pane, focus: false))
        let group = makeGroup(workspace, root: root, member: member)
        let service = try #require(group.sessionService)
        defer { service.shutdown() }
        #expect(group.showTerminal(panel: member, sessionID: "member", provider: "claude"))
        let lease = try #require(group.rendererLease)
        service.registry.update(sessionID: endsRoot ? "root-session" : "member") { $0.state = .ended }
        // No event-loop turn or web poll is needed to revoke an already focused renderer.
        #expect(group.rendererLease == nil)
        #expect(member.agentWorkspaceRendererLease == nil)
        #expect(!member.hostedView.debugPortalVisibleInUI)
        #expect(!lease.isCurrent)
        #expect(!lease.ownsPortal(in: pane))
        #expect(!group.showTerminal(panel: member, sessionID: "member", provider: "claude"))
    }

    @Test(arguments: [false, true])
    func replacingEitherSessionDoesNotRetargetItsSurvivingPTY(replacesRoot: Bool) throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let root = try #require(workspace.focusedTerminalPanel)
        let pane = try #require(workspace.paneId(forPanelId: root.id))
        let member = try #require(workspace.newTerminalSurface(inPane: pane, focus: false))
        let group = makeGroup(workspace, root: root, member: member)
        let service = try #require(group.sessionService)
        defer { service.shutdown() }
        #expect(group.showTerminal(panel: member, sessionID: "member", provider: "claude"))
        let surface = member.surface
        let endpoint = replacesRoot ? root : member
        service.registry.noteResumeInitiated(sessionID: "replacement", source: "claude",
            surfaceID: endpoint.id.uuidString, workspaceID: workspace.id.uuidString, workingDirectory: nil)
        #expect(group.rendererLease == nil)
        #expect(member.agentWorkspaceRendererLease == nil)
        #expect(member.surface === surface)
        #expect(!group.showTerminal(panel: member, sessionID: "member", provider: "claude"))
        #expect(service.registry.liveSessionSnapshot(surfaceID: endpoint.id.uuidString)?.sessionID == "replacement")
    }

    @Test func wrongProviderKnownDeadPIDAndShutdownCannotAuthorizeInput() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let root = try #require(workspace.focusedTerminalPanel)
        let pane = try #require(workspace.paneId(forPanelId: root.id))
        let member = try #require(workspace.newTerminalSurface(inPane: pane, focus: false))
        let group = makeGroup(workspace, root: root, member: member)
        let service = try #require(group.sessionService)
        defer { service.shutdown() }
        #expect(group.showTerminal(panel: member, sessionID: "member", provider: "claude"))
        #expect(!group.showTerminal(panel: member, sessionID: "member", provider: "codex"))
        #expect(group.rendererLease != nil)
        service.registry.update(sessionID: "member") { $0.pid = Int(Int32.max) }
        #expect(group.rendererLease == nil)
        #expect(!group.showTerminal(panel: member, sessionID: "member", provider: "claude"))
        #expect(group.showTerminal(panel: root, sessionID: "root-session", provider: "claude"))
        service.shutdown()
        #expect(group.rendererLease == nil)
    }

}
