/** Agent conversation state and the run queue (one run at a time, docs/AGENT.md#triggers). */

import { create } from "zustand";

import { refreshPlan } from "../../app/queryClient";
import { api } from "../../lib/api";
import { localNowIso } from "../../lib/dates";
import { streamSse } from "../../lib/sse";

export interface Change { id: number; summary: string; undone: boolean }

export type ChatItem =
  | { kind: "user" | "assistant" | "event" | "error"; id: number; text: string }
  | { kind: "tool"; id: number; name: string; args: Record<string, unknown>; done: boolean }
  | { kind: "changes"; id: number; changes: Change[] };

type RunRequest =
  | { trigger: "chat"; message: string }
  | { trigger: "task_event"; change_set_ids: number[] }
  | { trigger: "day_review" };

interface AgentStore {
  items: ChatItem[];
  running: boolean;
  loaded: boolean;
  reactToChanges: boolean;
  load: () => Promise<void>;
  send: (message: string) => void;
  notifyChange: (changeSetId: number) => void;
  dayReview: () => void;
  setReactToChanges: (on: boolean) => void;
  markUndone: (changeSetIds: number[]) => void;
}

const DEBOUNCE_MS = 4000;
const REACT_KEY = "planly:react-to-changes";

let nextId = 1;
let queue: RunRequest[] = [];
let pending: number[] = [];
let debounce: number | undefined;
let loading = false;

function readReact(): boolean {
  try {
    return localStorage.getItem(REACT_KEY) !== "off";
  } catch {
    return true;
  }
}

export const useAgent = create<AgentStore>((set, get) => {
  const push = (item: ChatItem) => set((s) => ({ items: [...s.items, item] }));
  const updateLastOf = (kind: ChatItem["kind"], fn: (item: ChatItem) => ChatItem) =>
    set((s) => {
      const i = s.items.findLastIndex((item) => item.kind === kind);
      if (i < 0) return {};
      const items = [...s.items];
      items[i] = fn(items[i]);
      return { items };
    });
  const appendToken = (text: string) =>
    updateLastOf("assistant", (item) => (item.kind === "assistant" ? { ...item, text: item.text + text } : item));
  const finishTool = () => updateLastOf("tool", (item) => (item.kind === "tool" ? { ...item, done: true } : item));

  async function run(request: RunRequest) {
    set({ running: true });
    let streamingText = false;
    try {
      const response = await fetch("/api/agent/runs", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ...request, now: localNowIso() }),
      });
      if (response.status === 409) {
        queue.unshift(request); // another tab or a server-side run is busy; retry shortly
        await new Promise((r) => setTimeout(r, 2000));
        return;
      }
      if (!response.ok) throw new Error((await response.json()).detail ?? response.statusText);

      for await (const { event, data } of streamSse(response)) {
        const d = data as Record<string, unknown>;
        if (event === "message") {
          push({ kind: d.role === "event" ? "event" : "user", id: nextId++, text: String(d.content) });
        } else if (event === "token") {
          if (streamingText) appendToken(String(d.text));
          else push({ kind: "assistant", id: nextId++, text: String(d.text) });
          streamingText = true;
        } else if (event === "tool_call") {
          streamingText = false;
          push({ kind: "tool", id: nextId++, name: String(d.name), args: (d.args as Record<string, unknown>) ?? {}, done: false });
        } else if (event === "tool_result") {
          finishTool();
          void refreshPlan(); // show the agent's moves as they happen
        } else if (event === "changes") {
          const changes = data as Change[];
          if (changes.length) push({ kind: "changes", id: nextId++, changes });
        } else if (event === "error") {
          push({ kind: "error", id: nextId++, text: String(d.message) });
        }
      }
    } catch (error) {
      push({ kind: "error", id: nextId++, text: error instanceof Error ? error.message : "The agent request failed." });
    } finally {
      set({ running: false });
      void refreshPlan();
      pump();
    }
  }

  function pump() {
    if (get().running || !queue.length) return;
    void run(queue.shift()!);
  }

  function enqueue(request: RunRequest) {
    queue.push(request);
    pump();
  }

  return {
    items: [],
    running: false,
    loaded: false,
    reactToChanges: readReact(),

    async load() {
      if (loading) return; // StrictMode and remounts call this more than once
      loading = true;
      try {
        const { messages } = await api.thread();
        const items: ChatItem[] = [];
        for (const m of messages) {
          if (m.role === "tool") continue;
          if (m.role === "assistant") {
            for (const name of m.tool_calls ?? []) items.push({ kind: "tool", id: nextId++, name, args: {}, done: true });
            if (m.content) items.push({ kind: "assistant", id: nextId++, text: m.content });
          } else {
            items.push({ kind: m.role, id: nextId++, text: m.content });
          }
        }
        set((s) => ({ items: [...items, ...s.items], loaded: true }));
      } catch {
        set({ loaded: true });
      }
    },

    send(message) {
      if (message.trim()) enqueue({ trigger: "chat", message: message.trim() });
    },

    notifyChange(changeSetId) {
      if (!get().reactToChanges) return;
      pending.push(changeSetId);
      window.clearTimeout(debounce);
      debounce = window.setTimeout(() => {
        const ids = pending;
        pending = [];
        enqueue({ trigger: "task_event", change_set_ids: ids });
      }, DEBOUNCE_MS);
    },

    dayReview() {
      enqueue({ trigger: "day_review" });
    },

    setReactToChanges(on) {
      try {
        localStorage.setItem(REACT_KEY, on ? "on" : "off");
      } catch {
        /* storage unavailable: keep it for this session only */
      }
      set({ reactToChanges: on });
    },

    markUndone(ids) {
      set((s) => ({
        items: s.items.map((item) =>
          item.kind === "changes"
            ? { ...item, changes: item.changes.map((c) => (ids.includes(c.id) ? { ...c, undone: true } : c)) }
            : item,
        ),
      }));
    },
  };
});

/** "Re-planning Fri 30 Oct" — what a tool call looks like in the chat. */
export function describeTool(name: string, args: Record<string, unknown>): string {
  const task = args.task_id ? ` #${args.task_id}` : "";
  switch (name) {
    case "replan_day": return args.pull_earlier ? "Pulling the day earlier" : "Re-planning the day";
    case "reschedule_task": return `Moving${task}`;
    case "create_task": return args.title ? `Adding “${args.title}”` : "Adding a task";
    case "update_task": return `Updating${task}`;
    case "list_tasks": return "Looking at your tasks";
    case "get_task": return `Reading${task}`;
    case "find_resources": return "Finding resources";
    case "save_resource": return "Saving a resource";
    case "evaluate_progress": return "Checking your progress";
    case "remember_preference": return "Remembering that";
    default: return name;
  }
}
