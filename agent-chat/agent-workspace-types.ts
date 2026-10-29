import type { AgentEvent } from "./types";

/** Group data is a projection of existing sessions; it never owns a process. */
export interface AgentWorkspaceMember {
  id: string;
  provider: "claude" | "codex";
  sessionId?: string;
  surfaceId?: string;
  label: string;
  relationship: "root" | "child" | "unassigned" | "observed";
  evidence: "binding" | "transcript-directory" | "spawn-result" | "spawn-tool" | "team-config" | "thread-spawn";
  state: "working" | "idle" | "needsInput" | "ended" | "unknown";
  conversation: boolean;
  tools: boolean;
  terminal: boolean;
}

export interface AgentWorkspaceSnapshot {
  version: 1;
  id: string;
  root: AgentWorkspaceMember;
  members: AgentWorkspaceMember[];
}

export interface AgentWorkspaceDetail {
  memberId: string;
  events: AgentEvent[];
  truncated: boolean;
}

export interface AgentWorkspaceSelection {
  version: 1;
  memberId: string | null;
  mode: "conversation" | "tools" | "terminal";
  collapsed: boolean;
}

/** Replayed snapshots never change the user's selected member. Missing members
 * remain selected so the UI can explain the lost binding, rather than send to root. */
export function restoreAgentWorkspaceSelection(raw: unknown): AgentWorkspaceSelection {
  const value = raw as Partial<AgentWorkspaceSelection> | null;
  if (value?.version !== 1) return { version: 1, memberId: null, mode: "conversation", collapsed: false };
  return {
    version: 1,
    memberId: typeof value.memberId === "string" ? value.memberId : null,
    mode: value.mode === "tools" || value.mode === "terminal" ? value.mode : "conversation",
    collapsed: value.collapsed === true,
  };
}
