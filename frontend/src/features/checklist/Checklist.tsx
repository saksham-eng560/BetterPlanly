import { ChevronRight, ListChecks, TriangleAlert } from "lucide-react";
import { AnimatePresence, motion } from "motion/react";
import { type CSSProperties, useState } from "react";

import { toggleDone } from "../../app/taskActions";
import { Checkbox } from "../../components/primitives";
import type { Task } from "../../lib/api";
import { endTime, formatDuration, relativeDay } from "../../lib/dates";
import { typeOf } from "../../lib/taskTypes";
import { MoveMenu } from "./MoveMenu";

import "./checklist.css";

const ROWS_BEFORE_MORE = 6;
const NO_SECTION = "Tasks";
const MISSED = "Missed";
const WIDGET_TINTS = [
  "var(--indigo)", "var(--cyan)", "var(--orange)", "var(--pink)", "var(--purple)",
  "var(--mint)", "var(--teal)", "var(--brown)",
];  // no yellow: too little contrast for a title on white

/** A stable colour per section name, so a box keeps its colour across weeks. */
function tintFor(section: string): string {
  if (section === MISSED) return "var(--red)";
  let hash = 0;
  for (const char of section) hash = (hash * 31 + char.charCodeAt(0)) | 0;
  return WIDGET_TINTS[Math.abs(hash) % WIDGET_TINTS.length];
}

function Row({ task, tint, today, onOpen }: { task: Task; tint: string; today: string; onOpen: (task: Task) => void }) {
  const kind = typeOf(task.type);
  // checked follows the click instantly; the server's answer takes over when the request settles
  const [optimistic, setOptimistic] = useState<boolean | null>(null);
  const done = optimistic ?? task.status === "done";
  const missed = !done && task.date !== null && task.date < today;
  const end = task.start ? endTime(task.start, task.duration_min) : null;
  const when = [
    task.date ? relativeDay(task.date, today) : null,
    task.start ? `${task.start}${end ? `–${end}` : ""}` : task.duration_min ? formatDuration(task.duration_min) : null,
    task.section ? null : kind.label,
  ].filter(Boolean).join(" · ");
  const subtasks = task.checklist.length ? `${task.checklist.filter((c) => c.done).length}/${task.checklist.length}` : null;

  return (
    <motion.li
      layout="position"
      className="check-row"
      data-done={done || undefined}
      style={{ "--tint": tint } as CSSProperties}
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0, transition: { duration: 0.12 } }}
      transition={{ type: "spring", duration: 0.4, bounce: 0.1 }}
    >
      <Checkbox
        checked={done}
        color={tint}
        label={`${done ? "Reopen" : "Complete"} “${task.title}”`}
        onChange={(checked) => {
          setOptimistic(checked);
          void toggleDone(task).finally(() => setOptimistic(null));
        }}
      />
      <button className="row-text" onClick={() => onOpen(task)}>
        <span className="row-title">{task.title}</span>
        {(when || subtasks) && (
          <span
            className="row-meta tabular"
            data-missed={missed || undefined}
            data-today={(!done && task.date === today) || undefined}
          >
            {when}
            {subtasks && <span className="row-sub">{when ? " · " : ""}{subtasks}</span>}
          </span>
        )}
      </button>
      <div className="row-actions">
        <MoveMenu task={task} />
        <button className="icon-btn secondary" aria-label={`Details and resources for “${task.title}”`} onClick={() => onOpen(task)}>
          <ChevronRight size={18} strokeWidth={2} />
        </button>
      </div>
    </motion.li>
  );
}

function Widget({ title, tasks, today, onOpen }: { title: string; tasks: Task[]; today: string; onOpen: (t: Task) => void }) {
  const [expanded, setExpanded] = useState(false);
  const tint = tintFor(title);
  const done = tasks.filter((t) => t.status === "done").length;
  const visible = expanded ? tasks : tasks.slice(0, ROWS_BEFORE_MORE);
  const Icon = title === MISSED ? TriangleAlert : ListChecks;

  return (
    <motion.section
      layout="position"
      className="widget"
      style={{ "--tint": tint } as CSSProperties}
      aria-label={title}
      transition={{ type: "spring", duration: 0.45, bounce: 0.12 }}
    >
      <header className="widget-head">
        <span className="widget-icon" aria-hidden="true"><Icon size={16} strokeWidth={2.25} /></span>
        <h3>{title}</h3>
        <span className="widget-count tabular" aria-label={`${done} of ${tasks.length} done`}>
          {title === MISSED ? tasks.length : `${done}/${tasks.length}`}
        </span>
      </header>
      <ul className="widget-list">
        <AnimatePresence initial={false}>
          {visible.map((task) => (
            <Row key={task.id} task={task} tint={tint} today={today} onOpen={onOpen} />
          ))}
        </AnimatePresence>
      </ul>
      {tasks.length > ROWS_BEFORE_MORE && (
        <button className="btn btn-plain widget-more" onClick={() => setExpanded((e) => !e)}>
          {expanded ? "Show less" : `Show all ${tasks.length}`}
        </button>
      )}
    </motion.section>
  );
}

/** Open tasks first; then by date (unscheduled last), time and their order in the source. */
function byUrgency(a: Task, b: Task): number {
  const doneA = a.status === "done" ? 1 : 0;
  const doneB = b.status === "done" ? 1 : 0;
  if (doneA !== doneB) return doneA - doneB;
  if (a.date !== b.date) return a.date === null ? 1 : b.date === null ? -1 : a.date < b.date ? -1 : 1;
  if (a.start !== b.start) return a.start === null ? -1 : b.start === null ? 1 : a.start < b.start ? -1 : 1;
  return a.position - b.position;
}

/** One box per section, in the order the sections appear in their source page. */
export function groupIntoWidgets(tasks: Task[], unscheduled: Task[], missed: Task[]): [string, Task[]][] {
  const missedIds = new Set(missed.map((t) => t.id));
  const pool = [...tasks, ...unscheduled]
    .filter((t) => !missedIds.has(t.id))
    .sort((a, b) => (a.plan_id ?? 0) - (b.plan_id ?? 0) || a.position - b.position || a.id - b.id);
  const groups = new Map<string, Task[]>();
  for (const task of pool) {
    const key = task.section ?? NO_SECTION;
    groups.set(key, [...(groups.get(key) ?? []), task]);
  }
  const ordered = [...groups].map(([name, tasks]) => [name, tasks.sort(byUrgency)] as [string, Task[]]);
  return missed.length ? [[MISSED, [...missed].sort(byUrgency)], ...ordered] : ordered;
}

export function Checklist({
  tasks,
  missed,
  unscheduled,
  today,
  onOpen,
}: {
  tasks: Task[];
  missed: Task[];
  unscheduled: Task[];
  today: string;
  onOpen: (task: Task) => void;
}) {
  const widgets = groupIntoWidgets(tasks, unscheduled, missed);
  const done = tasks.filter((t) => t.status === "done").length;
  return (
    <section className="checklist" aria-labelledby="checklist-title">
      <div className="section-head">
        <h2 id="checklist-title">Checklist</h2>
        {tasks.length > 0 && (
          <span className="progress tabular">{done} of {tasks.length} done</span>
        )}
      </div>
      {widgets.length ? (
        <div className="widgets">
          {widgets.map(([title, tasks]) => (
            <Widget key={title} title={title} tasks={tasks} today={today} onOpen={onOpen} />
          ))}
        </div>
      ) : (
        <p className="checklist-empty">Import a plan and each of its sections shows up here as its own box.</p>
      )}
    </section>
  );
}
