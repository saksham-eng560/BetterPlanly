import { ChevronRight } from "lucide-react";
import { AnimatePresence, motion } from "motion/react";
import { type CSSProperties, useState } from "react";

import { toggleDone } from "../../app/taskActions";
import { Checkbox } from "../../components/primitives";
import type { Task } from "../../lib/api";
import { endTime, formatDuration, relativeDay } from "../../lib/dates";
import { typeOf } from "../../lib/taskTypes";
import { MoveMenu } from "./MoveMenu";

import "./checklist.css";

function Row({ task, onOpen, showDate }: { task: Task; onOpen: (task: Task) => void; showDate: boolean }) {
  const kind = typeOf(task.type);
  // checked follows the click instantly; the server's answer takes over when the request settles
  const [optimistic, setOptimistic] = useState<boolean | null>(null);
  const done = optimistic ?? task.status === "done";
  const end = task.start ? endTime(task.start, task.duration_min) : null;
  const when = [
    showDate && task.date ? relativeDay(task.date) : null,
    task.start ? `${task.start}${end ? `–${end}` : ""}` : task.duration_min ? formatDuration(task.duration_min) : null,
    kind.label,
  ].filter(Boolean).join(" · ");
  const subtasks = task.checklist.length ? `${task.checklist.filter((c) => c.done).length}/${task.checklist.length}` : null;

  return (
    <motion.li
      layout="position"
      className="check-row"
      data-done={done || undefined}
      style={{ "--tint": kind.color } as CSSProperties}
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0, transition: { duration: 0.12 } }}
      transition={{ type: "spring", duration: 0.4, bounce: 0.1 }}
    >
      <Checkbox
        checked={done}
        color={kind.color}
        label={`${done ? "Reopen" : "Complete"} “${task.title}”`}
        onChange={(checked) => {
          setOptimistic(checked);
          void toggleDone(task).finally(() => setOptimistic(null));
        }}
      />
      <button className="row-text" onClick={() => onOpen(task)}>
        <span className="row-title">{task.title}</span>
        <span className="row-meta tabular" data-missed={showDate && !done ? true : undefined}>
          {when}
          {subtasks && <span className="row-sub"> · {subtasks}</span>}
        </span>
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

function Group({ title, tasks, onOpen, showDate = false }: { title: string; tasks: Task[]; onOpen: (t: Task) => void; showDate?: boolean }) {
  if (!tasks.length) return null;
  return (
    <section aria-label={title}>
      <h3 className="group-title">{title}</h3>
      <ul className="group">
        <AnimatePresence initial={false}>
          {tasks.map((task) => (
            <Row key={task.id} task={task} onOpen={onOpen} showDate={showDate} />
          ))}
        </AnimatePresence>
      </ul>
    </section>
  );
}

export function Checklist({
  dayLabel,
  dayTasks,
  missed,
  unscheduled,
  onOpen,
}: {
  dayLabel: string;
  dayTasks: Task[];
  missed: Task[];
  unscheduled: Task[];
  onOpen: (task: Task) => void;
}) {
  const open = dayTasks.filter((t) => t.status !== "done");
  const done = dayTasks.filter((t) => t.status === "done");
  return (
    <section className="checklist" aria-labelledby="checklist-title">
      <div className="section-head">
        <h2 id="checklist-title">Checklist</h2>
        {dayTasks.length > 0 && (
          <span className="progress tabular">{done.length} of {dayTasks.length} done</span>
        )}
      </div>
      <Group title="Missed" tasks={missed} onOpen={onOpen} showDate />
      <Group title={dayLabel} tasks={[...open, ...done]} onOpen={onOpen} />
      <Group title="Unscheduled" tasks={unscheduled} onOpen={onOpen} />
      {!dayTasks.length && !missed.length && !unscheduled.length && (
        <p className="checklist-empty">Ticked tasks and anything without a date will show up here.</p>
      )}
    </section>
  );
}
