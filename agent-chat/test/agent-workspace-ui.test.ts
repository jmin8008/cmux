import assert from "node:assert/strict";
import { createElement, useEffect, useState } from "react";
import { act, create, type ReactTestRenderer } from "react-test-renderer";
import type { AgentWorkspaceSnapshot } from "../agent-workspace-types";

Object.assign(globalThis, {
  IS_REACT_ACT_ENVIRONMENT: true,
  location: { search: "?group=1&workspace=workspace&surface=surface" },
  window: Object.assign(new EventTarget(), { __AGENT_CHAT_BASE__: "/token", webkit: { messageHandlers: { cmuxAgentWorkspace: { postMessage(value: unknown) { messages.push(value); } } } } }),
});
const messages: any[] = [];
let mounts = 0;
const { AgentWorkspace } = await import("../src/components/AgentWorkspace");
const { SessionContext } = await import("../src/context");
const root = { id: "local:codex:root", provider: "codex" as const, sessionId: "root", surfaceId: "surface", label: "Root", relationship: "root" as const, evidence: "binding" as const, state: "working" as const, conversation: true, tools: true, terminal: true };
const a = { ...root, id: "local:codex:a", sessionId: "a", label: "Child A", relationship: "child" as const, terminal: false };
const b = { ...a, id: "local:codex:b", sessionId: "b", label: "Child B" };
const c = { ...a, id: "local:codex:c", sessionId: "c", surfaceId: "surface-c", label: "Child C", terminal: true };
const snapshot: AgentWorkspaceSnapshot = { version: 1, id: root.id, root, members: [root, a, b, c] };
const pending = new Map<string, (value: Response) => void>();
globalThis.fetch = (async (input: string) => {
  const member = new URL(input, "http://localhost").searchParams.get("member");
  if (!member) return Response.json(snapshot);
  return new Promise<Response>((resolve) => pending.set(member, resolve));
}) as typeof fetch;
function MainComposer() {
  const [value, setValue] = useState("unsent main draft");
  useEffect(() => { mounts++; return () => { mounts--; }; }, []);
  return createElement("textarea", { value, onChange: (e: any) => setValue(e.target.value) });
}
let renderer: ReactTestRenderer;
await act(async () => {
  renderer = create(createElement(SessionContext.Provider, { value: { session: { id: "t-root" } } as any },
    createElement(AgentWorkspace, { children: createElement(MainComposer) })));
});
const button = (label: string) => renderer.root.findAllByType("button").find((node) => node.findAllByType("span").some((span) => span.children.includes(label)))!;
await act(async () => { button("Child A").props.onClick(); });
await act(async () => { button("Child B").props.onClick(); });
await act(async () => { pending.get(a.id)?.(Response.json({ memberId: a.id, events: [{ kind: "assistant", text: "late A result" }], truncated: false })); });
assert(!JSON.stringify(renderer.toJSON()).includes("late A result"), "late details must not overwrite the selected member");
await act(async () => { pending.get(b.id)?.(Response.json({ memberId: b.id, events: [{ kind: "assistant", text: "current B result" }], truncated: false })); });
assert(JSON.stringify(renderer.toJSON()).includes("current B result"));
assert.equal(renderer.root.findByType("textarea").props.value, "unsent main draft");
assert.equal(mounts, 1, "main conversation stays mounted through member changes");
assert.equal(button("Child B").props["aria-expanded"], true);
const terminal = renderer.root.findAllByType("button").find((n) => n.props.role === "tab" && n.children.includes("Original terminal"));
assert.equal(terminal?.props.disabled, true, "trace-only child cannot synthesize a terminal");
await act(async () => { button("Child C").props.onClick(); });
const liveTerminal = () => renderer.root.findAllByType("button").find((n) => n.props.role === "tab" && n.children.includes("Original terminal"))!;
await act(async () => { liveTerminal().props.onClick(); });
assert(messages.some((m) => m.action === "terminal" && m.sessionId === "c" && m.surfaceId === "surface-c"));
const collapse = () => renderer.root.findByType("header").findAllByType("button").find((n) => n.props["aria-expanded"] !== undefined)!;
await act(async () => { collapse().props.onClick(); });
assert.equal(messages.at(-1).action, "dismiss-terminal", "collapsing the selected terminal releases its native renderer");
await act(async () => { collapse().props.onClick(); });
assert.equal(messages.at(-1).action, "terminal", "expanding restores only the selected exact terminal binding");
assert.equal(messages.at(-1).sessionId, "c");
const beforeEnd = messages.length;
// Reproduce a stale server capability too: state alone must revoke the renderer.
snapshot.members = snapshot.members.map((m) => m.id === c.id ? { ...m, state: "ended", terminal: true } : m);
await act(async () => { await new Promise((resolve) => setTimeout(resolve, 2700)); });
assert(messages.slice(beforeEnd).some((m) => m.action === "dismiss-terminal"), "ended selected member releases raw input even if its surface survives");
assert.equal(liveTerminal().props.disabled, true);
assert(!messages.slice(beforeEnd).some((m) => m.action === "terminal"));
assert.equal(renderer.root.findAllByType("button").find((n) => n.props.role === "tab" && n.children.includes("Conversation"))?.props["aria-selected"], true);
await act(async () => { window.dispatchEvent(new CustomEvent("cmux-agent-workspace-binding-lost", { detail: { rootInvalid: true } })); });
assert.equal(renderer.root.findByType("header").findAllByType("button")[0].props.disabled, true);
assert(!messages.some((m) => ["send", "start", "spawn", "stop"].includes(m.action)), "projection emits no lifecycle commands");
await act(async () => renderer.unmount());
assert.equal(mounts, 0);
console.log("agent workspace UI assertions passed");
