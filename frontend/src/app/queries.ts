import { useQuery } from "@tanstack/react-query";

import { api } from "../lib/api";
import { addDays } from "../lib/dates";

export const useWeekTasks = (start: string) =>
  useQuery({ queryKey: ["tasks", "range", start], queryFn: () => api.tasks(start, addDays(start, 6)) });

export const useMissed = (today: string) =>
  useQuery({ queryKey: ["tasks", "missed", today], queryFn: () => api.missed(today) });

export const useUnscheduled = () => useQuery({ queryKey: ["tasks", "unscheduled"], queryFn: api.unscheduled });

export const useTask = (id: number | null) =>
  useQuery({ queryKey: ["tasks", "one", id], queryFn: () => api.task(id!), enabled: id !== null });

export const useAppState = (today: string) =>
  useQuery({ queryKey: ["state", today], queryFn: () => api.state(today), refetchInterval: 30_000 });

export const useHistory = (enabled: boolean) =>
  useQuery({ queryKey: ["history"], queryFn: () => api.history(30), enabled });
