// Fixture app-server: no provider is started and no user data is read.
const root = { id: "root-session-123", source: "cli", status: { type: "idle" } };
const child = { id: "child-session-456", status: { type: "active" }, agentNickname: "Reviewer",
  source: { subAgent: { thread_spawn: { parent_thread_id: root.id, depth: 1 } } } };
const server = Bun.serve({
  hostname: "127.0.0.1", port: 0,
  fetch(req, server) { return server.upgrade(req) ? undefined : new Response("WebSocket required", { status: 400 }); },
  websocket: {
    message(ws, raw) {
      const request = JSON.parse(String(raw));
      if (request.id === undefined) return;
      const result = request.method === "thread/loaded/list" ? { data: [child.id, root.id] }
        : request.method === "thread/resume" ? { thread: request.params.threadId === root.id ? root : child } : {};
      ws.send(JSON.stringify({ id: request.id, result }));
    },
  },
});
console.log(`ws://127.0.0.1:${server.port}`);
