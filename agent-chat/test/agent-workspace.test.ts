import { afterEach, describe, expect, test } from "bun:test";
import { mkdtempSync, mkdirSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { discoverAgentWorkspace } from "../agent-workspace";
import { restoreAgentWorkspaceSelection } from "../agent-workspace-types";
import { resolveCodexChildTranscript, type TranscriptSource } from "../transcript-sources";
import { AGENT_CHAT_LOCALES } from "../src/i18n";
import { agentWorkspaceText, agentWorkspaceState } from "../src/agent-workspace-i18n";

const dirs: string[] = [];
const jsonl = (...records: unknown[]) => records.map((r) => JSON.stringify(r)).join("\n") + "\n";
function fixture(agent: "claude" | "codex" = "claude") {
  const dir = mkdtempSync(join(tmpdir(), "cmux-agent-workspace-")); dirs.push(dir);
  const root: TranscriptSource = { agent, sessionId: "root-session-123", surfaceId: "A1A1A1A1-A1A1-A1A1-A1A1-A1A1A1A1A1A1", path: join(dir, "root-session-123.jsonl"), updatedAt: 1 };
  writeFileSync(root.path, jsonl({ type: "user", uuid: "u", message: { content: "Main prompt" } }));
  const binding = { id: root.sessionId, agentKind: agent, terminalID: root.surfaceId, state: "working" };
  return { dir, root, binding };
}
afterEach(() => dirs.splice(0).forEach((dir) => rmSync(dir, { recursive: true, force: true })));

describe("agent workspace projection", () => {
  test("requires exact provider, root session and current workspace surface binding", async () => {
    const { root, binding } = fixture();
    await expect(discoverAgentWorkspace(root, [], () => null)).rejects.toThrow("binding_missing");
    await expect(discoverAgentWorkspace(root, [{ ...binding, id: "new-session" }], () => null)).rejects.toThrow();
    await expect(discoverAgentWorkspace(root, [{ ...binding, agentKind: "codex" }], () => null)).rejects.toThrow();
    await expect(discoverAgentWorkspace(root, [{ ...binding, terminalID: "other" }], () => null)).rejects.toThrow();
  });

  test("Claude child transcript retains its sidechain messages without inventing a terminal", async () => {
    const { dir, root, binding } = fixture();
    const subagents = join(dir, root.sessionId, "subagents"); mkdirSync(subagents, { recursive: true });
    writeFileSync(join(subagents, "agent-a123.jsonl"), jsonl(
      { type: "user", uuid: "c1", sessionId: root.sessionId, agentId: "a123", isSidechain: true, message: { content: "Inspect parser" } },
      { type: "assistant", uuid: "c2", sessionId: root.sessionId, agentId: "a123", isSidechain: true, message: { content: [{ type: "text", text: "Found the issue" }] } },
    ));
    const group = await discoverAgentWorkspace(root, [binding], () => null);
    const child = group.snapshot.members.find((m) => m.relationship === "child")!;
    expect(child.conversation).toBe(true); expect(child.terminal).toBe(false); expect(child.sessionId).toBeUndefined();
    expect(child.state).toBe("unknown");
    const detail = await group.detail(child.id);
    expect(detail?.events).toContainEqual({ kind: "assistant", text: "Found the issue" });
    expect((await group.detail(group.snapshot.root.id))?.events).not.toContainEqual({ kind: "assistant", text: "Found the issue" });
  });

  test("rejects child symlinks and mismatched agent metadata", async () => {
    const { dir, root, binding } = fixture();
    const subagents = join(dir, root.sessionId, "subagents"); mkdirSync(subagents, { recursive: true });
    writeFileSync(join(dir, "outside.jsonl"), jsonl({ sessionId: root.sessionId, agentId: "bad" }));
    symlinkSync(join(dir, "outside.jsonl"), join(subagents, "agent-bad.jsonl"));
    writeFileSync(join(subagents, "agent-other.jsonl"), jsonl({ sessionId: "another-parent", agentId: "other" }));
    const group = await discoverAgentWorkspace(root, [binding], () => null);
    expect(group.snapshot.members).toHaveLength(1);
    expect(await group.detail("../../outside.jsonl")).toBeNull();
  });

  test("spawn replay deduplicates observations and detach never means completed", async () => {
    const { root, binding } = fixture();
    const spawn = { type: "assistant", uuid: "spawn", message: { content: [{ type: "tool_use", id: "task-1", name: "Agent", input: { description: "Background work" } }] } };
    writeFileSync(root.path, jsonl(spawn, spawn, { type: "user", uuid: "result", message: { content: [{ type: "tool_result", tool_use_id: "task-1", content: "Launched in background" }] } }, { type: "system", subtype: "turn_duration", durationMs: 20 }));
    const group = await discoverAgentWorkspace(root, [binding], () => null);
    const observations = group.snapshot.members.filter((m) => m.relationship === "observed");
    expect(observations).toHaveLength(1); expect(observations[0].state).toBe("unknown");
    expect(observations[0].conversation).toBe(false); expect(observations[0].terminal).toBe(false);
    expect((await group.detail(observations[0].id))?.events.some((e) => e.kind === "tool-end")).toBe(true);
    expect(group.snapshot.root.state).toBe("working");
  });

  test("same-workspace sessions remain unassigned unless explicit spawn-result evidence exists", async () => {
    const { root, binding } = fixture("codex");
    const peer = { ...binding, id: "peer-session-456", terminalID: "other-terminal" };
    writeFileSync(root.path, jsonl({ type: "session_meta", payload: { parentSessionId: peer.id } }));
    const group = await discoverAgentWorkspace(root, [binding, peer], () => null);
    expect(group.snapshot.members.find((m) => m.sessionId === peer.id)?.relationship).toBe("unassigned");
    writeFileSync(root.path, jsonl(
      { type: "response_item", payload: { type: "function_call", call_id: "spawn1", name: "spawn_agent", arguments: "{}" } },
      { type: "response_item", payload: { type: "function_call_output", call_id: "spawn1", output: JSON.stringify({ agent_id: peer.id }) } },
    ));
    const linked = await discoverAgentWorkspace(root, [binding, peer], () => null);
    expect(linked.snapshot.members.find((m) => m.sessionId === peer.id)?.relationship).toBe("child");
    expect(linked.snapshot.members.filter((m) => m.sessionId === peer.id)).toHaveLength(1);
    expect(linked.snapshot.members.filter((m) => m.relationship === "observed")).toHaveLength(0);
  });

  test("a resolver result for another provider cannot grant conversation capability", async () => {
    const { root, binding } = fixture("codex");
    const peer = { ...binding, id: "peer-session-456", terminalID: "other-terminal" };
    const group = await discoverAgentWorkspace(root, [binding, peer], () => ({ ...root, agent: "claude", sessionId: peer.id }));
    expect(group.snapshot.members.find((m) => m.sessionId === peer.id)?.conversation).toBe(false);
  });

  test("Codex trace-only child requires its own explicit parent metadata", () => {
    const { dir, root } = fixture("codex");
    const childId = "child-session-123";
    const day = join(dir, "sessions", "2026", "10", "29"); mkdirSync(day, { recursive: true });
    const path = join(day, `rollout-time-${childId}.jsonl`);
    const write = (parent: string) => writeFileSync(path, jsonl({ type: "session_meta", payload: {
      id: childId, source: { subagent: { thread_spawn: { parent_thread_id: parent } } },
    } }));
    write("another-parent");
    expect(resolveCodexChildTranscript(root, childId, { codexHome: dir })).toBeNull();
    write(root.sessionId);
    const source = resolveCodexChildTranscript(root, childId, { codexHome: dir });
    expect(source?.sessionId).toBe(childId); expect(source?.surfaceId).toBeUndefined();
    expect(resolveCodexChildTranscript(root, "../../outside", { codexHome: dir })).toBeNull();
  });

  test("Claude Teams uses explicit lead/session identity and retains unknown capabilities", async () => {
    const { dir, root, binding } = fixture();
    const teams = join(dir, "teams");
    for (const team of ["mine", "foreign"]) mkdirSync(join(teams, team), { recursive: true });
    const config = { leadSessionId: root.sessionId, leadAgentId: "lead@mine", members: [
      { agentId: "lead@mine", name: "Lead", agentType: "team-lead" },
      { agentId: "reviewer@mine", name: "Reviewer", sessionId: "teammate-session-123" },
      { agentId: "trace-only@mine", name: "Planner" },
    ] };
    writeFileSync(join(teams, "mine", "config.json"), JSON.stringify(config));
    writeFileSync(join(teams, "foreign", "config.json"), JSON.stringify({ ...config, leadSessionId: "another-session" }));
    writeFileSync(join(dir, "teammate-session-123.jsonl"), jsonl({ type: "assistant", sessionId: "teammate-session-123", uuid: "t1", message: { content: [{ type: "text", text: "Team finding" }] } }));
    const group = await discoverAgentWorkspace(root, [binding], () => null, { claudeTeamsDirectory: teams });
    const members = group.snapshot.members.filter((m) => m.evidence === "team-config");
    expect(members).toHaveLength(2);
    const reviewer = members.find((m) => m.label === "Reviewer")!;
    expect(reviewer.conversation).toBe(true); expect(reviewer.terminal).toBe(false);
    expect((await group.detail(reviewer.id))?.events).toContainEqual({ kind: "assistant", text: "Team finding" });
    const planner = members.find((m) => m.label === "Planner")!;
    expect(planner.state).toBe("unknown"); expect(planner.conversation).toBe(false); expect(planner.terminal).toBe(false);
    // The config alone cannot grant another session's transcript contents.
    writeFileSync(join(dir, "teammate-session-123.jsonl"), jsonl({ sessionId: "wrong-session" }));
    const changed = await discoverAgentWorkspace(root, [binding], () => null, { claudeTeamsDirectory: teams });
    expect(changed.snapshot.members.find((m) => m.id === reviewer.id)?.conversation).toBe(false);
  });

  test("Codex Teams resolves out-of-order descendants and excludes foreign roots/forks", async () => {
    const { dir, root, binding } = fixture("codex");
    const workspaceID = "22222222-2222-4222-8222-222222222222";
    mkdirSync(join(dir, "codex"));
    const path = join(dir, "codex", root.surfaceId!.toLowerCase() + ".json");
    const snapshot = { version: 1, workspaceID, surfaceID: root.surfaceId, updatedAt: Date.now(), threads: [
      { id: "grandchild-session", parentThreadID: "child-session", label: "Nested reviewer", status: "idle" },
      { id: "child-session", parentThreadID: root.sessionId, label: "Reviewer", status: "active" },
      { id: "other-session", parentThreadID: "foreign-root", status: "active" },
      { id: "fork-session", forkedFromId: root.sessionId },
    ] };
    writeFileSync(path, JSON.stringify(snapshot));
    const options = { workspaceID, codexTeamsDirectory: dir };
    const group = await discoverAgentWorkspace(root, [binding], () => null, options);
    expect(group.snapshot.members.map((m) => m.sessionId).sort()).toEqual([root.sessionId, "child-session", "grandchild-session"].sort());
    expect(group.snapshot.members.find((m) => m.label === "Reviewer")?.state).toBe("working");
    expect(group.snapshot.members.find((m) => m.label === "Nested reviewer")?.state).toBe("idle");
    expect(group.snapshot.members.every((m) => m.relationship === "root" || !m.terminal)).toBe(true);
    writeFileSync(path, JSON.stringify({ ...snapshot, updatedAt: Date.now() - 60_000 }));
    const stale = await discoverAgentWorkspace(root, [binding], () => null, options);
    expect(stale.snapshot.members.find((m) => m.label === "Reviewer")?.state).toBe("unknown");
    const wrongWorkspace = await discoverAgentWorkspace(root, [binding], () => null, { ...options, workspaceID: root.surfaceId });
    expect(wrongWorkspace.snapshot.members).toHaveLength(1);
  });

  test("ended and replaced bindings retain history but never terminal input capability", async () => {
    const { root, binding } = fixture("codex");
    const ended = { ...binding, id: "ended-session", terminalID: "other-surface", state: "ended" };
    const old = { ...binding, id: "old-session-123", terminalID: "reused-surface" };
    const current = { ...old, id: "new-session-456" };
    const group = await discoverAgentWorkspace(root, [binding, current, old, ended], () => null);
    expect(group.snapshot.members.find((m) => m.sessionId === ended.id)?.terminal).toBe(false);
    expect(group.snapshot.members.find((m) => m.sessionId === old.id)?.terminal).toBe(false);
    expect(group.snapshot.members.find((m) => m.sessionId === current.id)?.terminal).toBe(true);
    await expect(discoverAgentWorkspace(root, [{ ...binding, state: "ended" }], () => null)).rejects.toThrow("binding_missing");
    await expect(discoverAgentWorkspace(root, [{ ...binding, id: "replacement-root" }, binding], () => null)).rejects.toThrow("binding_missing");
  });

  test("selection restoration retains a missing member and rejects unknown versions", () => {
    const selected = { version: 1, memberId: "local:codex:missing", mode: "tools", collapsed: true } as const;
    expect(restoreAgentWorkspaceSelection(selected)).toEqual(selected);
    expect(restoreAgentWorkspaceSelection({ ...selected, version: 2 }).memberId).toBeNull();
    expect(restoreAgentWorkspaceSelection({ ...selected, mode: "send" }).mode).toBe("conversation");
  });

  test("all supported locales provide feature messages", () => {
    for (const locale of AGENT_CHAT_LOCALES) {
      for (const state of ["working", "idle", "needsInput", "ended", "empty", "unknown"] as const) {
        expect(agentWorkspaceState(state, [locale]).length).toBeGreaterThan(0);
      }
      for (const key of ["group", "main", "members", "conversation", "tools", "terminal", "hide", "unassigned", "observed", "unknown", "unavailable", "missing", "loading", "readOnly", "truncated", "collapsed", "expanded"] as const) {
        expect(agentWorkspaceText(key, [locale]).length).toBeGreaterThan(0);
      }
    }
  });
});
