import {
  BookOpen,
  Briefcase,
  Circle,
  Dumbbell,
  GraduationCap,
  Heart,
  type LucideIcon,
  Repeat,
  ShoppingBag,
  Users,
} from "lucide-react";

import type { TaskType } from "./api";

export const TASK_TYPES: Record<TaskType, { label: string; icon: LucideIcon; color: string }> = {
  study: { label: "Study", icon: GraduationCap, color: "var(--type-study)" },
  work: { label: "Work", icon: Briefcase, color: "var(--type-work)" },
  reading: { label: "Reading", icon: BookOpen, color: "var(--type-reading)" },
  fitness: { label: "Fitness", icon: Dumbbell, color: "var(--type-fitness)" },
  meeting: { label: "Meeting", icon: Users, color: "var(--type-meeting)" },
  habit: { label: "Habit", icon: Repeat, color: "var(--type-habit)" },
  errand: { label: "Errand", icon: ShoppingBag, color: "var(--type-errand)" },
  personal: { label: "Personal", icon: Heart, color: "var(--type-personal)" },
  other: { label: "Other", icon: Circle, color: "var(--type-other)" },
};

export function typeOf(type: string) {
  return TASK_TYPES[type as TaskType] ?? TASK_TYPES.other;
}
