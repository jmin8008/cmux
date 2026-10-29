import { open, readdir, realpath } from "node:fs/promises";
import { dirname, join } from "node:path";
import { claudeTeamMembers, codexTeamMembers } from "./agent-workspace-teams";
import { parseTranscriptText } from "./adapters/transcript";
import { resolveSessionTranscript, resolveCodexChildTranscript, type TranscriptSource } from "./transcript-sources";
import type { AgentWorkspaceDetail, AgentWorkspaceMember, AgentWorkspaceSnapshot } from "./agent-workspace-types";
import type { AgentEvent } from "./types";

export interface WorkspaceSessionBinding {
  id: string;
  agentKind: string;
  terminalID?: string;
  title?: string;
  state?: string;
}
interface MemberSource { member: AgentWorkspaceMember; source?: TranscriptSource; events?: AgentEvent[]; childTranscript?: boolean }
const LIMIT = 4 * 1024 * 1024;
type TranscriptLog = ReturnType<typeof parseTranscriptText> & { rows: any[]; truncated: boolean };
const logCache = new Map<string, { stamp: string; bytes: number; log: TranscriptLog }>();
const SESSION_ID = /^[\w-]{8,128}$/;
const state = (value?: string): AgentWorkspaceMember["state"] =>
  value === "working" || value === "idle" || value === "needsInput" || value === "ended" ? value : "unknown";
const key = (provider: string, id: string) => `local:${provider}:${id}`;

/** Bounded reads keep a large transcript from blocking the sidecar event loop. */
async function transcript(source: TranscriptSource, child = false, metadataOnly = false): Promise<TranscriptLog> {
  const file = await open(source.path, "r");
  try {
    const stat = await file.stat();
    const size = stat.size;
    const limit = metadataOnly ? 64 * 1024 : LIMIT;
    const cacheKey = `${source.agent}:${source.path}:${child}:${metadataOnly}`;
    const stamp = `${stat.mtimeMs}:${size}`;
    const cached = logCache.get(cacheKey);
    if (cached?.stamp === stamp) return cached.log;
    const buffer = Buffer.alloc(Math.min(size, limit));
    await file.read(buffer, 0, buffer.length, metadataOnly ? 0 : Math.max(0, size - limit));
    let text = buffer.toString("utf8");
    if (!metadataOnly && size > limit) text = text.slice(text.indexOf("\n") + 1);
    const rows = text.split("\n").flatMap((line) => {
      try { return [JSON.parse(line)]; } catch { return []; }
    });
    // Claude's regular parser intentionally hides sidechains in the ROOT log.
    // Here the source is the verified child's own file, so retain its messages.
    const normalized = child && source.agent === "claude"
      ? rows.map((row) => JSON.stringify({ ...row, isSidechain: false })).join("\n") : text;
    const log = { ...parseTranscriptText(source.agent, normalized), rows, truncated: size > limit };
    logCache.delete(cacheKey);
    logCache.set(cacheKey, { stamp, bytes: buffer.length, log });
    let bytes = [...logCache.values()].reduce((sum, item) => sum + item.bytes, 0);
    for (const [key, item] of logCache) {
      if (bytes <= 8 * 1024 * 1024 && logCache.size <= 128) break;
      logCache.delete(key); bytes -= item.bytes;
    }
    return log;
  } finally { await file.close(); }
}

/** Discovers only evidence-backed children, plus explicitly unassigned terminals
 * already scoped by the host to this workspace. cwd and PID never imply lineage. */
export async function discoverAgentWorkspace(
  root: TranscriptSource,
  bindings: WorkspaceSessionBinding[],
  resolveSession: (id: string) => TranscriptSource | null = (id) => resolveSessionTranscript(id) ?? resolveCodexChildTranscript(root, id),
  options: { workspaceID?: string; claudeTeamsDirectory?: string; codexTeamsDirectory?: string } = {},
): Promise<{ snapshot: AgentWorkspaceSnapshot; detail(memberId: string): Promise<AgentWorkspaceDetail | null> }> {
  const binding = bindings.find((b) => b.id === root.sessionId && b.agentKind === root.agent
    && b.terminalID?.toUpperCase() === root.surfaceId?.toUpperCase());
  if (!binding) throw new Error("binding_missing");
  const rootMember: AgentWorkspaceMember = {
    id: key(root.agent, root.sessionId), provider: root.agent, sessionId: root.sessionId,
    surfaceId: root.surfaceId, label: binding.title || root.sessionId, relationship: "root",
    evidence: "binding", state: state(binding.state), conversation: true, tools: true, terminal: true,
  };
  const entries = new Map<string, MemberSource>([[rootMember.id, { member: rootMember, source: root }]]);
  const rootLog = await transcript(root);
  if (root.agent === "claude") {
    const directory = join(dirname(root.path), root.sessionId, "subagents");
    try {
      const canonical = await realpath(directory);
      const files = (await readdir(directory)).filter((name) => /^agent-[\w-]+\.jsonl$/.test(name)).sort().slice(0, 100);
      for (const name of files) {
        const path = join(directory, name);
        // Never follow a child symlink outside the agent's own subagent directory.
        if (await realpath(path) !== join(canonical, name)) continue;
        const agentId = name.slice(6, -6);
        const source = { ...root, path, surfaceId: undefined };
        const log = await transcript(source, true, true);
        if (!log.rows.some((row) => row.sessionId === root.sessionId && row.agentId === agentId)) continue;
        const id = key("claude", `${root.sessionId}:child:${agentId}`);
        entries.set(id, { source, childTranscript: true, member: {
          id, provider: "claude", label: log.title || agentId, relationship: "child",
          evidence: "transcript-directory", state: "unknown", conversation: true, tools: true, terminal: false,
        } });
      }
    } catch { /* no child transcript capability for this session */ }
  }
  if (root.agent === "claude") {
    for (const teammate of await claudeTeamMembers(root.sessionId, options.claudeTeamsDirectory)) {
      const childID = key("claude", `${root.sessionId}:child:${teammate.agentId}`);
      const child = entries.get(childID);
      const id = child?.member.id ?? (teammate.sessionId ? key("claude", teammate.sessionId)
        : key("claude", `${root.sessionId}:team:${teammate.team}:${teammate.agentId}`));
      const b = teammate.sessionId ? bindings.find((b) => b.agentKind === "claude" && b.id === teammate.sessionId) : undefined;
      const candidate = teammate.sessionId ? resolveSession(teammate.sessionId) : undefined;
      let source = child?.source ?? (candidate?.agent === "claude" && candidate.sessionId === teammate.sessionId ? candidate : undefined);
      if (!source && teammate.sessionId) {
        // A verified team session can expose a transcript before its first hook.
        // Only the provider's sibling file and its matching metadata are accepted.
        const path = join(dirname(root.path), `${teammate.sessionId}.jsonl`);
        try {
          if (await realpath(path) === join(await realpath(dirname(root.path)), `${teammate.sessionId}.jsonl`)) {
            const proposed = { ...root, path, sessionId: teammate.sessionId, surfaceId: undefined };
            if ((await transcript(proposed, false, true)).rows.some((row) => row.sessionId === teammate.sessionId)) source = proposed;
          }
        } catch { /* Config membership is still visible without a transcript. */ }
      }
      entries.set(id, { source, childTranscript: child?.childTranscript, member: {
        id, provider: "claude", sessionId: teammate.sessionId, surfaceId: b?.terminalID,
        label: teammate.label, relationship: "child", evidence: "team-config", state: state(b?.state),
        conversation: !!source, tools: !!source, terminal: !!b?.terminalID,
      } });
    }
  } else if (root.agent === "codex") {
    for (const child of await codexTeamMembers(root.sessionId, root.surfaceId, options.workspaceID, options.codexTeamsDirectory)) {
      const candidate = resolveSession(child.id) ?? resolveCodexChildTranscript({ ...root, sessionId: child.parentThreadID }, child.id);
      const source = candidate?.agent === "codex" && candidate.sessionId === child.id ? candidate : undefined;
      const b = bindings.find((b) => b.agentKind === "codex" && b.id === child.id);
      const id = key("codex", child.id);
      entries.set(id, { source, member: {
        id, provider: "codex", sessionId: child.id, surfaceId: b?.terminalID,
        label: b?.title || child.label || child.id, relationship: "child", evidence: "thread-spawn",
        state: state(b?.state ?? (child.status === "active" ? "working" : child.status)),
        conversation: !!source, tools: !!source, terminal: !!b?.terminalID,
      } });
    }
  }
  // Only an explicit spawn result establishes a Codex child. parentSessionId
  // elsewhere can be a conversational fork and is deliberately not consulted.
  const spawnCalls = new Set<string>();
  const linkedSpawnCalls = new Set<string>();
  for (const row of rootLog.rows) {
    const item = row.type === "response_item" ? row.payload : null;
    if (item?.type === "function_call" && typeof item.call_id === "string" && /(?:^|\.)spawn_agent$/.test(item.name ?? "")) spawnCalls.add(item.call_id);
    if (item?.type !== "function_call_output" || !spawnCalls.has(item.call_id)) continue;
    let result: { agent_id?: string };
    try { result = typeof item.output === "string" ? JSON.parse(item.output) : item.output; } catch { continue; }
    const id = result?.agent_id;
    if (!id || !SESSION_ID.test(id)) continue;
    linkedSpawnCalls.add(item.call_id);
    const candidate = resolveSession(id);
    const source = candidate?.agent === "codex" && candidate.sessionId === id ? candidate : undefined;
    const childBinding = bindings.find((b) => b.id === id && b.agentKind === "codex");
    const memberId = key("codex", id);
    if (entries.has(memberId)) continue;
    entries.set(memberId, { source: source?.agent === "codex" ? source : undefined, member: {
      id: memberId, provider: "codex", sessionId: id, surfaceId: childBinding?.terminalID,
      label: childBinding?.title || id, relationship: "child", evidence: "spawn-result",
      state: state(childBinding?.state), conversation: !!source, tools: !!source, terminal: !!childBinding?.terminalID,
    } });
  }
  // A spawn tool without an addressable child is an observation, not an invented
  // session. Tool completion (including background detach) does not prove success.
  for (const event of rootLog.events) {
    if (event.kind !== "tool-start" || !/^(Task|Agent|(?:.*\.)?spawn_agent)$/.test(event.name) || linkedSpawnCalls.has(event.toolId)) continue;
    const id = `${rootMember.id}:run:${event.toolId}`;
    entries.set(id, { events: rootLog.events.filter((e) => (e.kind === "tool-start" || e.kind === "tool-end") && e.toolId === event.toolId), member: {
      id, provider: root.agent, label: event.detail || event.name, relationship: "observed", evidence: "spawn-tool",
      state: "unknown", conversation: false, tools: true, terminal: false,
    } });
  }
  for (const b of bindings) {
    if (b.agentKind !== "claude" && b.agentKind !== "codex") continue;
    const id = key(b.agentKind, b.id);
    if (entries.has(id)) continue;
    const candidate = resolveSession(b.id);
    const source = candidate?.agent === b.agentKind && candidate.sessionId === b.id ? candidate : undefined;
    entries.set(id, { source: source?.agent === b.agentKind ? source : undefined, member: {
      id, provider: b.agentKind, sessionId: b.id, surfaceId: b.terminalID, label: b.title || b.id,
      relationship: "unassigned", evidence: "binding", state: state(b.state), conversation: !!source,
      tools: !!source, terminal: !!b.terminalID,
    } });
  }
  return {
    snapshot: { version: 1, id: rootMember.id, root: rootMember, members: [...entries.values()].map((entry) => entry.member) },
    async detail(memberId) {
      const entry = entries.get(memberId);
      if (!entry) return null;
      if (entry.events) return { memberId, events: entry.events, truncated: rootLog.truncated };
      if (!entry.source) return { memberId, events: [], truncated: false };
      const log = await transcript(entry.source, entry.childTranscript === true);
      return { memberId, events: log.events, truncated: log.truncated };
    },
  };
}
