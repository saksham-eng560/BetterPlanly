import { CalendarPlus, Check, Flag, Link2, ListChecks } from "lucide-react";
import { AnimatePresence, motion } from "motion/react";
import { type CSSProperties, type ReactElement, useEffect, useState } from "react";

import type { Task } from "../../lib/api";
import { endTime, formatDuration, minutesOf, timeOf } from "../../lib/dates";
import { typeOf } from "../../lib/taskTypes";

import "./timeline.css";

const FREE_GAP_MIN = 30;
const layoutSpring = { type: "spring", duration: 0.45, bounce: 0.12 } as const;

function useNowMinutes(active: boolean): number {
  const read = () => new Date().getHours() * 60 + new Date().getMinutes();
  const [now, setNow] = useState(read);
  useEffect(() => {
    if (!active) return;
    const timer = window.setInterval(() => setNow(read()), 30_000);
    return () => window.clearInterval(timer);
  }, [active]);
  return now;
}

export function TaskCard({ task, onOpen, compact = false }: { task: Task; onOpen: (task: Task) => void; compact?: boolean }) {
  const kind = typeOf(task.type);
  const Icon = kind.icon;
  const done = task.status === "done";
  const checked = task.checklist.filter((c) => c.done).length;
  const end = task.start ? endTime(task.start, task.duration_min) : null;
  const height = compact || !task.duration_min ? undefined : `${Math.min(9, Math.max(3.75, task.duration_min / 16))}rem`;

  return (
    <button
      className="task-card"
      data-done={done || undefined}
      style={{ "--tint": kind.color, minHeight: height } as CSSProperties}
      onClick={() => onOpen(task)}
      aria-label={`${task.title}, ${kind.label}${task.start ? `, ${task.start}` : ""}${done ? ", done" : ""}`}
    >
      <span className="glyph" aria-hidden="true">
        {done ? <Check size={16} strokeWidth={2.5} /> : <Icon size={16} strokeWidth={2} />}
      </span>
      <span className="body">
        <span className="title">{task.title}</span>
        <span className="meta tabular">
          {task.start ? `${task.start}${end ? `–${end}` : ""}` : task.duration_min ? formatDuration(task.duration_min) : "Anytime"}
          {task.start && task.duration_min ? ` · ${formatDuration(task.duration_min)}` : ""}
          {` · ${kind.label}`}
        </span>
      </span>
      <span className="badges" aria-hidden="true">
        {task.priority === "high" && !done && <Flag size={14} className="flag" fill="currentColor" />}
        {task.checklist.length > 0 && (
          <span className="badge tabular"><ListChecks size={14} />{checked}/{task.checklist.length}</span>
        )}
        {task.resources.length > 0 && (
          <span className="badge tabular"><Link2 size={14} />{task.resources.length}</span>
        )}
      </span>
    </button>
  );
}

export function DayTimeline({
  tasks,
  isToday,
  onOpen,
  onImport,
}: {
  tasks: Task[];
  isToday: boolean;
  onOpen: (task: Task) => void;
  onImport: () => void;
}) {
  const now = useNowMinutes(isToday);
  const anytime = tasks.filter((t) => !t.start);
  const timed = tasks.filter((t) => t.start).sort((a, b) => minutesOf(a.start!) - minutesOf(b.start!));

  if (!tasks.length) {
    return (
      <div className="empty-day">
        <CalendarPlus size={44} strokeWidth={1.5} aria-hidden="true" />
        <h3>Nothing planned</h3>
        <p>Import a plan file or ask the agent to plan this day.</p>
        <button className="btn btn-tinted" onClick={onImport}>Import a plan</button>
      </div>
    );
  }

  // the now-line goes before the first task that starts now or later
  const nowIndex = isToday ? timed.findIndex((t) => minutesOf(t.start!) >= now) : -2;
  const nowLine = (
    <motion.li layout="position" key="now" className="now-line" aria-label={`Now, ${timeOf(now)}`}>
      <span className="time tabular">{timeOf(now)}</span>
      <span className="rule" />
    </motion.li>
  );

  const rows: ReactElement[] = [];
  timed.forEach((task, i) => {
    const prev = timed[i - 1];
    const gap = prev ? minutesOf(task.start!) - (minutesOf(prev.start!) + (prev.duration_min ?? 0)) : 0;
    if (i === nowIndex) rows.push(nowLine);
    if (gap >= FREE_GAP_MIN) {
      rows.push(
        <motion.li layout="position" key={`gap-${task.id}`} className="free" transition={layoutSpring}>
          <span className="time" />
          <span className="free-label">Free · {formatDuration(gap)}</span>
        </motion.li>,
      );
    }
    rows.push(
      <motion.li key={task.id} className="slot" layout transition={layoutSpring} {...enterExit}>
        <span className="time tabular">{task.start}</span>
        <TaskCard task={task} onOpen={onOpen} />
      </motion.li>,
    );
  });
  if (nowIndex === -1) rows.push(nowLine);

  return (
    <section className="timeline" aria-label="Timeline">
      {anytime.length > 0 && (
        <div className="anytime">
          <h3 className="group-title">Anytime</h3>
          <motion.ul className="anytime-list">
            <AnimatePresence mode="popLayout" initial={false}>
              {anytime.map((task) => (
                <motion.li key={task.id} layout transition={layoutSpring} {...enterExit}>
                  <TaskCard task={task} onOpen={onOpen} compact />
                </motion.li>
              ))}
            </AnimatePresence>
          </motion.ul>
        </div>
      )}
      {timed.length > 0 && (
        <ol className="timed">
          <AnimatePresence mode="popLayout" initial={false}>
            {rows}
          </AnimatePresence>
        </ol>
      )}
    </section>
  );
}

const enterExit = {
  initial: { opacity: 0, transform: "translateY(6px) scale(0.98)" },
  animate: { opacity: 1, transform: "translateY(0px) scale(1)" },
  exit: { opacity: 0, transform: "scale(0.98)", transition: { duration: 0.15 } },
};
