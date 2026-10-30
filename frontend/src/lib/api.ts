/** Typed client for the Planly backend (docs/API.md). */

export type TaskType =
  | "study" | "work" | "reading" | "fitness" | "meeting" | "habit" | "errand" | "personal" | "other";
export type Priority = "high" | "medium" | "low";
export type Status = "todo" | "done" | "skipped";

export interface ChecklistItem { id: number; title: string; done: boolean; position: number }
export interface Resource { id: number; title: string; url: string | null; kind: string; note: string; added_by: string }

export interface Task {
  id: number;
  plan_id: number | null;
  title: string;
  type: TaskType;
  date: string | null;
  start: string | null;
  duration_min: number | null;
  priority: Priority;
  status: Status;
  completed_at: string | null;
  notes: string;
  tags: string[];
  checklist: ChecklistItem[];
  resources: Resource[];
}

export interface ChangeSet {
  id: number;
  actor: "user" | "agent" | "import";
  summary: string;
  created_at: string;
  undone_at: string | null;
  undo_of: number | null;
}

export interface TaskChange { task: Task | null; change_set: ChangeSet | null }

export interface ImportResult {
  plan: { id: number; title: string; source: string; source_ref: string };
  created: number;
  updated: number;
  unchanged: number;
  change_set: ChangeSet | null;
}

export interface AppState {
  tasks: number;
  done: number;
  missed: number;
  last_change_at: string | null;
  agent: { model: string; reachable: boolean; busy: boolean };
  notion_configured: boolean;
  web_search_enabled: boolean;
}

export interface ThreadMessage {
  role: "user" | "assistant" | "event" | "tool";
  content: string;
  name?: string;
  tool_calls?: string[];
}

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
    public errors: string[] = [],
  ) {
    super(message);
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`/api${path}`, {
    ...init,
    headers: init?.body instanceof FormData ? init.headers : { "Content-Type": "application/json", ...init?.headers },
  });
  if (!response.ok) {
    let detail = response.statusText;
    let errors: string[] = [];
    try {
      const body = await response.json();
      detail = typeof body.detail === "string" ? body.detail : JSON.stringify(body.detail);
      errors = body.errors ?? [];
    } catch {
      /* not JSON */
    }
    throw new ApiError(response.status, detail, errors);
  }
  return response.json() as Promise<T>;
}

const post = <T>(path: string, body?: unknown) =>
  request<T>(path, { method: "POST", body: body === undefined ? undefined : JSON.stringify(body) });

export const api = {
  tasks: (start: string, end: string) => request<Task[]>(`/tasks?start=${start}&end=${end}`),
  missed: (before: string) => request<Task[]>(`/tasks?missed_before=${before}`),
  unscheduled: () => request<Task[]>("/tasks?unscheduled=true"),
  task: (id: number) => request<Task>(`/tasks/${id}`),
  createTask: (body: Partial<Task> & { title: string }) => post<TaskChange>("/tasks", body),
  complete: (id: number) => post<TaskChange>(`/tasks/${id}/complete`),
  uncomplete: (id: number) => post<TaskChange>(`/tasks/${id}/uncomplete`),
  reschedule: (id: number, date: string | null, keepTime = true) =>
    post<TaskChange>(`/tasks/${id}/reschedule`, { date, keep_time: keepTime }),
  setChecklist: (itemId: number, done: boolean) =>
    request<TaskChange>(`/checklist/${itemId}`, { method: "PATCH", body: JSON.stringify({ done }) }),
  history: (limit = 30) => request<ChangeSet[]>(`/history?limit=${limit}`),
  undo: (changeSetId: number) => post<ChangeSet>(`/history/${changeSetId}/undo`),
  importFile: (file: File) => {
    const form = new FormData();
    form.append("file", file);
    return request<ImportResult>("/imports/file", { method: "POST", body: form });
  },
  importNotion: (databaseId: string) => post<ImportResult>("/imports/notion", { database_id: databaseId }),
  state: (today: string) => request<AppState>(`/state?today=${today}`),
  thread: () => request<{ messages: ThreadMessage[] }>("/agent/thread"),
};
