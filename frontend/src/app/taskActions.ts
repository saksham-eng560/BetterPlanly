/** User actions on tasks: optimistic where it matters, always undoable, and the agent hears about them. */

import { queryClient, refreshPlan } from "./queryClient";
import { toast } from "../components/toasts";
import { useAgent } from "../features/chat/agentStore";
import { ApiError, api, type Task } from "../lib/api";
import { relativeDay } from "../lib/dates";

async function patchCachedTask(id: number, patch: Partial<Task>) {
  // a refetch already in flight (e.g. from an agent run) would overwrite the optimistic value
  await queryClient.cancelQueries({ queryKey: ["tasks"] });
  queryClient.setQueriesData<Task[]>({ queryKey: ["tasks"] }, (tasks) =>
    tasks?.map((t) => (t.id === id ? { ...t, ...patch } : t)),
  );
}

function fail(error: unknown) {
  toast({ message: error instanceof ApiError ? error.message : "Something went wrong.", tone: "error" });
  void refreshPlan();
}

export async function undo(changeSetId: number) {
  try {
    await api.undo(changeSetId);
    useAgent.getState().markUndone([changeSetId]);
    toast({ message: "Undone" });
  } catch (error) {
    fail(error);
  }
  await refreshPlan();
}

function undoAction(changeSetId: number | undefined) {
  return changeSetId ? { label: "Undo", run: () => void undo(changeSetId) } : undefined;
}

export async function toggleDone(task: Task) {
  const done = task.status !== "done";
  await patchCachedTask(task.id, { status: done ? "done" : "todo" });
  try {
    const { change_set } = done ? await api.complete(task.id) : await api.uncomplete(task.id);
    if (change_set) {
      toast({ message: `${done ? "Completed" : "Reopened"} “${task.title}”`, action: undoAction(change_set.id) });
      useAgent.getState().notifyChange(change_set.id);
    }
  } catch (error) {
    fail(error);
  }
  await refreshPlan();
}

export async function moveTask(task: Task, date: string | null) {
  await patchCachedTask(task.id, { date });
  try {
    const { change_set } = await api.reschedule(task.id, date);
    if (change_set) {
      toast({ message: `Moved “${task.title}” to ${date ? relativeDay(date) : "Unscheduled"}`, action: undoAction(change_set.id) });
      useAgent.getState().notifyChange(change_set.id);
    }
  } catch (error) {
    fail(error);
  }
  await refreshPlan();
}

export async function toggleChecklistItem(itemId: number, done: boolean) {
  try {
    await api.setChecklist(itemId, done);
  } catch (error) {
    fail(error);
  }
  await refreshPlan();
}
