import { open, readdir, realpath } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

const SESSION_ID = /^[\w-]{8,128}$/;
const UUID = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;

async function boundedJSON(path: string): Promise<any> {
  const file = await open(path, "r");
  try {
    if ((await file.stat()).size > 512 * 1024) return null;
    return JSON.parse(await file.readFile("utf8"));
  } finally { await file.close(); }
}

export interface ClaudeTeamMember {
  team: string;
  agentId: string;
  label: string;
  sessionId?: string;
}

/** Claude owns this live config. Only its explicit lead-session binding proves
 * membership; a similar name, directory, PID or project is never a substitute. */
export async function claudeTeamMembers(rootSessionId: string, directory = join(process.env.CLAUDE_CONFIG_DIR ?? join(homedir(), ".claude"), "teams")): Promise<ClaudeTeamMember[]> {
  const members: ClaudeTeamMember[] = [];
  try {
    const canonical = await realpath(directory);
    const teams = (await readdir(directory)).filter((name) => /^[\w-]+$/.test(name)).sort().slice(0, 100);
    for (const team of teams) {
      try {
        const path = join(directory, team, "config.json");
        if (await realpath(path) !== join(canonical, team, "config.json")) continue;
        const config = await boundedJSON(path);
        if (config?.leadSessionId !== rootSessionId || !Array.isArray(config.members)) continue;
        for (const member of config.members.slice(0, 200)) {
          if (typeof member?.agentId !== "string" || !/^[\w@.-]{1,256}$/.test(member.agentId)
            || member.agentId === config.leadAgentId || member.agentType === "team-lead") continue;
          members.push({ team, agentId: member.agentId,
            label: typeof member.name === "string" && member.name ? member.name : member.agentId,
            sessionId: typeof member.sessionId === "string" && SESSION_ID.test(member.sessionId)
              && member.sessionId !== rootSessionId ? member.sessionId : undefined });
        }
      } catch { /* An atomically replaced/deleted config is retried next poll. */ }
    }
  } catch { /* Provider does not expose Teams config. */ }
  return members;
}

export interface CodexTeamMember { id: string; parentThreadID: string; label?: string; status?: string }

/** The existing watcher exports app-server thread_spawn metadata, including
 * children whose spawn calls have rolled out of the bounded root transcript. */
export async function codexTeamMembers(rootSessionId: string, surfaceID: string | undefined, workspaceID: string | undefined,
  directory = process.env.CMUX_AGENT_WORKSPACE_DIRECTORY): Promise<CodexTeamMember[]> {
  if (!directory || !surfaceID || !workspaceID || !UUID.test(surfaceID) || !UUID.test(workspaceID)) return [];
  try {
    const path = join(directory, "codex", surfaceID.toLowerCase() + ".json");
    if (await realpath(path) !== join(await realpath(directory), "codex", surfaceID.toLowerCase() + ".json")) return [];
    const snapshot = await boundedJSON(path);
    if (snapshot?.version !== 1 || snapshot.surfaceID?.toUpperCase() !== surfaceID.toUpperCase()
      || snapshot.workspaceID?.toUpperCase() !== workspaceID.toUpperCase() || !Array.isArray(snapshot.threads)) return [];
    const known = new Set([rootSessionId]);
    const members: CodexTeamMember[] = [];
    const candidates = snapshot.threads.slice(0, 2000);
    // Child notifications can precede parents. Resolve the proven graph without
    // relying on arrival order, depth guesses or a shared app-server connection.
    for (let pass = 0; pass < candidates.length; pass++) {
      let changed = false;
      for (const thread of candidates) {
        if (typeof thread?.id !== "string" || !SESSION_ID.test(thread.id) || known.has(thread.id)
          || typeof thread.parentThreadID !== "string" || !known.has(thread.parentThreadID)) continue;
        known.add(thread.id); changed = true;
        members.push({ id: thread.id, parentThreadID: thread.parentThreadID,
          label: typeof thread.label === "string" ? thread.label : undefined,
          // A stopped watcher must not report a perpetually working child.
          status: Date.now() - snapshot.updatedAt < 30_000 && typeof thread.status === "string" ? thread.status : undefined });
      }
      if (!changed) break;
    }
    return members;
  } catch { return []; }
}
