import assert from "node:assert/strict";
import { mkdtemp, mkdir, writeFile, readFile, rm, chmod } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Real sidecar HTTP path, with an isolated registry CLI fixture. No agent runs.
const directory = await mkdtemp(join(tmpdir(), "cmux-agent-group-http-"));
const surface = "A1111111-1111-1111-1111-111111111111";
const workspace = "B2222222-2222-2222-2222-222222222222";
const sessionId = "root-session-123";
const transcript = join(directory, `${sessionId}.jsonl`);
const stateFile = join(directory, "server-state.json");
const calls = join(directory, "calls.jsonl");
const cli = join(directory, "cmux-fixture");
const rows = (...values: unknown[]) => values.map((v) => JSON.stringify(v)).join("\n") + "\n";
await writeFile(transcript, rows({ type: "user", uuid: "u1", sessionId, message: { content: "Main conversation" } }));
await writeFile(join(directory, "claude-hook-sessions.json"), JSON.stringify({ sessions: { [sessionId]: { surfaceId: surface, transcriptPath: transcript, updatedAt: 1 } } }));
await writeFile(cli, `#!${process.execPath}\nimport { appendFileSync } from "node:fs";
appendFileSync(${JSON.stringify(calls)}, JSON.stringify(process.argv.slice(2)) + "\\n");
const params = JSON.parse(process.argv[4]);
console.log(JSON.stringify({ sessions: params.workspace_id === ${JSON.stringify(workspace)} ? [{ id: ${JSON.stringify(sessionId)}, agentKind: "claude", terminalID: ${JSON.stringify(surface)}, state: "working", title: "Main" }] : [] }));\n`);
await chmod(cli, 0o700);
const proc = Bun.spawn([process.execPath, "server.ts"], {
  cwd: join(import.meta.dir, ".."), stdin: "ignore", stdout: "ignore", stderr: "ignore",
  env: { ...process.env, CMUX_AGENT_CHAT_PORT: "0", CMUX_AGENT_CHAT_TOKEN: "group-fixture", CMUX_AGENT_CHAT_STATE_FILE: stateFile, CMUX_AGENT_HOOK_STATE_DIR: directory, CMUX_CLAUDE_HOOK_STATE_PATH: join(directory, "claude-hook-sessions.json"), CMUX_BUNDLED_CLI_PATH: cli, CMUX_AGENT_MODELS_URL: "http://127.0.0.1:1/unused" },
});
try {
  let port: number | undefined;
  const deadline = Date.now() + 10_000;
  while (!port && Date.now() < deadline) {
    try { port = JSON.parse(await readFile(stateFile, "utf8")).port; } catch {}
    if (!port) await Bun.sleep(25);
  }
  assert(port, "sidecar must report its ephemeral port");
  const base = `http://127.0.0.1:${port}`;
  if (Bun.argv.includes("--preview")) {
    const subagents = join(directory, sessionId, "subagents"); await mkdir(subagents, { recursive: true });
    await writeFile(join(subagents, "agent-reviewer.jsonl"), rows(
      { type: "user", uuid: "child-u", sessionId, agentId: "reviewer", isSidechain: true, message: { content: "Review login implementation" } },
      { type: "assistant", uuid: "child-a", sessionId, agentId: "reviewer", isSidechain: true, message: { content: [{ type: "text", text: "The session binding is preserved. No additional terminal is needed for this review." }] } },
    ));
    const preview = `${base}/group-fixture/terminal/${surface}?group=1&surface=${surface}&workspace=${workspace}&root=${sessionId}`;
    await writeFile("/tmp/cmux-jmin-agents-preview-url", preview);
    console.log(preview);
    await Bun.sleep(60_000);
  }

  if (!Bun.argv.includes("--preview")) {
  const query = `surface=${surface}&workspace=${workspace}&root=${sessionId}`;
  assert.equal((await fetch(`${base}/api/agent-workspace?${query}`)).status, 404);
  const url = `${base}/group-fixture/api/agent-workspace?${query}`;
  const response = await fetch(url); assert.equal(response.status, 200);
  const group = await response.json() as any;
  assert.equal(group.members.length, 1); assert.equal(group.root.sessionId, sessionId);
  assert.equal((await fetch(`${url}&member=../../private-file`)).status, 404);
  const detail = await (await fetch(`${url}&member=${encodeURIComponent(group.root.id)}`)).json() as any;
  assert(detail.events.some((event: any) => event.text === "Main conversation"));
  assert.equal((await fetch(url.replace(workspace, "C3333333-3333-3333-3333-333333333333"))).status, 409);
  assert.equal((await fetch(url.replace(`root=${sessionId}`, "root=changed-session-123"))).status, 409);
  assert.equal((await fetch(url, { headers: { Origin: "https://untrusted.example" } })).status, 403);
  const requests = (await readFile(calls, "utf8")).trim().split("\n").map((line) => JSON.parse(line));
  assert(requests.every((args: string[]) => args[1] === "mobile.chat.sessions"), "viewing group can only list sessions, never spawn/send/stop");
  console.log("agent workspace authenticated HTTP, binding scope, detail and lifecycle assertions passed");
  }
} finally {
  proc.kill(); await proc.exited;
  await rm(directory, { recursive: true, force: true });
}
