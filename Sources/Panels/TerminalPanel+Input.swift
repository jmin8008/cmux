import CmuxTerminal

@MainActor
extension TerminalPanel {
    // MARK: - Terminal-specific methods

    @discardableResult
    func sendText(_ text: String) -> Bool {
        sendTextResult(text).accepted
    }

    func sendTextResult(_ text: String) -> TerminalSurface.TextSendResult {
        resumeForExplicitInputIfNeeded()
        return surface.sendTextResult(text)
    }

    func sendInput(_ text: String) {
        _ = sendInputResult(text)
    }

    @discardableResult
    func sendInputResult(_ text: String) -> TerminalSurface.InputSendResult {
        resumeForExplicitInputIfNeeded()
        return surface.sendInputResult(text)
    }

    @discardableResult
    func sendNamedKeyResult(_ keyName: String) -> TerminalSurface.NamedKeySendResult {
        resumeForExplicitInputIfNeeded()
        return surface.sendNamedKey(keyName)
    }

    @discardableResult
    func sendNamedKey(_ keyName: String) -> Bool {
        switch sendNamedKeyResult(keyName) {
        case .sent, .queued:
            return true
        case .unknownKey, .inputQueueFull, .surfaceUnavailable, .processExited:
            return false
        }
    }

    func performBindingAction(_ action: String) -> Bool {
        guard !isAgentHibernated else { return false }
        return surface.performExplicitInputBindingAction(action)
    }

    @discardableResult
    func clearScreenKeepingScrollback() -> Bool {
        resumeForExplicitInputIfNeeded()
        return surface.clearScreenKeepingScrollback()
    }

    private func resumeForExplicitInputIfNeeded() {
        guard isAgentHibernated else { return }
        _ = requestAgentHibernationResume(focus: false)
    }

    /// A viewer attaching from another device is visiting this terminal, the
    /// same as selecting its tab here. Resume a hibernated agent so the attach
    /// mirrors a live runtime instead of a torn-down surface.
    func resumeAgentHibernationForRemoteAttach() {
        guard isAgentHibernated else { return }
        _ = requestAgentHibernationResume(focus: false)
    }

    @discardableResult
    func requestAgentHibernationResume(focus: Bool) -> Bool {
        guard isAgentHibernated else { return false }
        if let onRequestAgentHibernationResume {
            return onRequestAgentHibernationResume(focus)
        }
        return prepareAgentHibernationResume().didResume
    }

}
