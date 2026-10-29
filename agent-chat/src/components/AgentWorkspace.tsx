import { useEffect, useState, type ReactNode } from "react";
import { useCtx } from "../context";
import { ChatMarkdown } from "../ChatMarkdown";
import { preferenceStorage } from "../browser-storage";
import { agentWorkspaceText as t, agentWorkspaceState } from "../agent-workspace-i18n";
import { restoreAgentWorkspaceSelection, type AgentWorkspaceDetail, type AgentWorkspaceMember, type AgentWorkspaceSnapshot } from "../../agent-workspace-types";
import type { AgentEvent } from "../../types";

export function agentWorkspaceEnabled(): boolean {
  return typeof location !== "undefined" && new URLSearchParams(location.search).get("group") === "1";
}

/** Native host validates exact session/surface binding before focusing. */
export function agentWorkspaceNative(action: "terminal" | "hide" | "dismiss-terminal", member?: AgentWorkspaceMember): boolean {
  const bridge = (window as any).webkit?.messageHandlers?.cmuxAgentWorkspace;
  if (!bridge) return false;
  bridge.postMessage({ action, sessionId: member?.sessionId, surfaceId: member?.surfaceId, provider: member?.provider });
  return true;
}

function Activity({ event }: { event: AgentEvent }) {
  if (event.kind === "user" || event.kind === "assistant" || event.kind === "thinking" || event.kind === "delta") {
    return <div className={`agent-workspace-event ${event.kind}`}><ChatMarkdown text={event.text} /></div>;
  }
  if (event.kind === "tool-start" || event.kind === "tool-end") {
    return <details className="agent-workspace-tool"><summary>{event.name || event.toolId}</summary><pre>{event.detail}</pre></details>;
  }
  if (event.kind === "status") return <p>{event.text}</p>;
  if (event.kind === "error") return <p role="status">{event.message}</p>;
  return null;
}

/** Selecting a member never changes the main session context or input target. */
export function AgentWorkspace({ children }: { children: ReactNode }) {
  const { session } = useCtx();
  const params = new URLSearchParams(location.search);
  const rootId = params.get("root") ?? session?.id?.replace(/^t-/, "");
  const storageKey = `agentui.group.v1:${params.get("workspace")}:${rootId ?? params.get("surface")}`;
  const [selection, setSelection] = useState(() => {
    try { return restoreAgentWorkspaceSelection((window as any).__AGENT_WORKSPACE_SELECTION__ ?? JSON.parse(preferenceStorage.getItem(storageKey) ?? "null")); }
    catch { return restoreAgentWorkspaceSelection(null); }
  });
  const [snapshot, setSnapshot] = useState<AgentWorkspaceSnapshot | null>(null);
  const [detail, setDetail] = useState<AgentWorkspaceDetail | null>(null);
  const [error, setError] = useState(false);
  const [detailError, setDetailError] = useState(false);
  const query = new URLSearchParams({ surface: params.get("surface") ?? "", workspace: params.get("workspace") ?? "", ...(rootId ? { root: rootId } : {}) });
  const endpoint = `${window.__AGENT_CHAT_BASE__ ?? ""}/api/agent-workspace?${query}`;
  useEffect(() => {
    preferenceStorage.setItem(storageKey, JSON.stringify(selection));
    (window as any).webkit?.messageHandlers?.cmuxAgentWorkspace?.postMessage({ action: "selection", selection });
  }, [selection, storageKey]);
  useEffect(() => {
    let cancelled = false;
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout>;
    const refresh = async () => {
      try {
        const response = await fetch(endpoint, { signal: controller.signal });
        if (!response.ok) throw new Error("binding_missing");
        const value: AgentWorkspaceSnapshot = await response.json();
        if (!cancelled) { setSnapshot(value); setError(false); }
      } catch { if (!cancelled) setError(true); }
      if (!cancelled) timer = setTimeout(refresh, 2500);
    };
    void refresh();
    return () => { cancelled = true; controller.abort(); clearTimeout(timer); };
  }, [endpoint]);
  const selected = snapshot?.members.find((m) => m.id === selection.memberId);
  useEffect(() => {
    setDetail(null);
    setDetailError(false);
    if (selection.collapsed || selection.mode !== "terminal") agentWorkspaceNative("dismiss-terminal");
    if (!selection.memberId || selection.collapsed || selection.mode === "terminal") return;
    let cancelled = false;
    let timer: ReturnType<typeof setTimeout>;
    const controller = new AbortController();
    const refresh = async () => {
      try {
        const response = await fetch(`${endpoint}&member=${encodeURIComponent(selection.memberId!)}`, { signal: controller.signal });
        if (!response.ok) throw new Error("member_missing");
        const value: AgentWorkspaceDetail = await response.json();
        if (!cancelled && value.memberId === selection.memberId) { setDetail(value); setDetailError(false); }
      } catch { if (!cancelled) setDetailError(true); }
      if (!cancelled) timer = setTimeout(refresh, 2500);
    };
    void refresh();
    return () => { cancelled = true; controller.abort(); clearTimeout(timer); };
  }, [endpoint, selection.memberId, selection.collapsed, selection.mode]);
  useEffect(() => {
    const lost = error || (snapshot && selection.memberId && !selected)
      || (selection.mode === "terminal" && selected && (!selected.terminal || selected.state === "ended"));
    if (lost) {
      agentWorkspaceNative("dismiss-terminal");
      if (selection.mode === "terminal") setSelection((s) => ({ ...s, mode: "conversation" }));
    } else if (selection.mode === "terminal" && !selection.collapsed && selected?.terminal) {
      agentWorkspaceNative("terminal", selected);
    }
  }, [error, snapshot?.id, selected?.id, selected?.sessionId, selected?.surfaceId, selected?.terminal, selected?.state, selection.mode, selection.collapsed]);
  useEffect(() => {
    const bindingLost = (event: Event) => {
      setSelection((s) => ({ ...s, mode: "conversation" }));
      if ((event as CustomEvent).detail?.rootInvalid) setError(true);
    };
    window.addEventListener("cmux-agent-workspace-binding-lost", bindingLost);
    return () => window.removeEventListener("cmux-agent-workspace-binding-lost", bindingLost);
  }, []);
  const select = (member: AgentWorkspaceMember) => setSelection((old) => ({ ...old, memberId: old.memberId === member.id ? null : member.id, mode: member.conversation ? "conversation" : "tools", collapsed: false }));
  const showTerminal = (member: AgentWorkspaceMember) => { if (member.terminal && member.state !== "ended") agentWorkspaceNative("terminal", member); };
  return <section className="agent-workspace" aria-label={t("group")}>
    <header className="agent-workspace-header">
      <strong>{t("main")}</strong>
      <button type="button" disabled={!snapshot || error || !snapshot.root.terminal || snapshot.root.state === "ended"} onClick={() => snapshot && showTerminal(snapshot.root)}>{t("terminal")}</button>
      <button type="button" aria-expanded={!selection.collapsed} onClick={() => setSelection((s) => ({ ...s, collapsed: !s.collapsed }))}>{t(selection.collapsed ? "collapsed" : "expanded")}</button>
      <button type="button" onClick={() => agentWorkspaceNative("hide")}>{t("hide")}</button>
    </header>
    <div className="agent-workspace-main">{children}</div>
    {!selection.collapsed && <aside className="agent-workspace-members" aria-label={t("members")}>
      {error ? <p role="status">{t("missing")}</p> : !snapshot ? <p role="status">{t("loading")}</p> : <>
        {snapshot.members.length === 1 && <p className="agent-workspace-hint">{agentWorkspaceState("empty")}</p>}
        <nav aria-label={t("members")}>{snapshot.members.filter((m) => m.relationship !== "root").map((member) =>
          <button key={member.id} type="button" aria-expanded={member.id === selection.memberId} onClick={() => select(member)} title={member.id}>
            <span>{member.label}</span><small>{member.relationship === "unassigned" ? t("unassigned") : member.relationship === "observed" ? t("observed") : member.provider} · {agentWorkspaceState(member.state)}</small>
          </button>)}
        </nav>
        {selection.memberId && <section className="agent-workspace-detail" aria-label={selected?.label || t("missing")}>
          {!selected || detailError ? <p role="status">{t("missing")}</p> : <>
            <div className="agent-workspace-tabs" role="tablist">
              {(["conversation", "tools", "terminal"] as const).map((mode) => <button key={mode} type="button" role="tab" aria-selected={selection.mode === mode}
                disabled={!selected[mode] || (mode === "terminal" && selected.state === "ended")} title={!selected[mode] ? t("unavailable") : undefined}
                onClick={() => { setSelection((s) => ({ ...s, mode })); if (mode === "terminal" && selection.mode === "terminal") showTerminal(selected); }}>{t(mode)}</button>)}
            </div>
            {selection.mode !== "terminal" && <p className="agent-workspace-hint">{t("readOnly")}</p>}
            {selection.mode !== "terminal" && <div className="agent-workspace-events" role="tabpanel">
              {!detail ? <p>{t("loading")}</p> : <>
                {detail.truncated && <p>{t("truncated")}</p>}
                {detail.events.filter((event) => selection.mode !== "tools" || event.kind === "tool-start" || event.kind === "tool-end").map((event, i) => <Activity key={i} event={event} />)}
              </>}
            </div>}
          </>}
        </section>}
      </>}
    </aside>}
  </section>;
}
