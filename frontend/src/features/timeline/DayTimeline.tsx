import { CalendarPlus, Check, Flag, Link2, ListChecks } from "lucide-react";
import { AnimatePresence, motion } from "motion/react";
import { type CSSProperties, type ReactElement, useEffect, useState } from "react";

import { DurPill } from "../../components/primitives";
import type { Task } from "../../lib/api";
import { elapsedShare, endTime, formatDuration, minutesOf, nowMinutes, timeOf } from "../../lib/dates";
import { typeOf } from "../../lib/taskTypes";

import "./timeline.css";

const FREE_GAP_MIN = 30;
const layoutSpring = { type: "spring", duration: 0.45, bounce: 0.12 } as const;

function useNowMinutes(active: boolean): number {
  const [now, setNow] = useState(nowMinutes);
  useEffect(() => {
    if (!active) return;
    const timer = window.setInterval(() => setNow(nowMinutes()), 30_000);
    return () => window.clearInterval(timer);
  }, [active]);
  return now;
}

export function TaskCard({
  task,
  onOpen,
  compact = false,
  now = null,
}: {
  task: Task;
  onOpen: (task: Task) => void;
  compact?: boolean;
  /** minutes since midnight when the card is on today's timeline (drives the lime ruler) */
  now?: number | null;
}) {
  const kind = typeOf(task.type);
  const Icon = kind.icon;
  const done = task.status === "done";
  const flagged = task.priority === "high" && !done;
  const checked = task.checklist.filter((c) => c.done).length;
  const duration = task.duration_min ?? 0;
  const end = task.start ? endTime(task.start, task.duration_min) : null;
  // regular = the reference card: big start/end numerals, a duration pill on a hairline and a tick ruler
  const regular = !compact && !!task.start && duration >= 45;
  const minHeight = regular ? `${Math.min(10, Math.max(6, duration / 16))}rem` : undefined;

  return (
    <button
      className="task-card"
      data-size={regular ? "regular" : "compact"}
      data-done={done || undefined}
      style={{ "--tint": kind.color, minHeight } as CSSProperties}
      onClick={() => onOpen(task)}
      aria-label={`${task.title}, ${kind.label}${task.start ? `, ${task.start}` : ""}${flagged ? ", high priority" : ""}${done ? ", done" : ""}`}
    >
      <span className="glyph" aria-hidden="true">
        {done ? <Check size={16} strokeWidth={2.5} /> : <Icon size={16} strokeWidth={2} />}
      </span>
      <span className="title">{task.title}</span>
      <span className="badges tabular" aria-hidden="true">
        {flagged && <Flag size={13} className="flag" fill="currentColor" />}
        {regular && <span className="kind">{kind.label}</span>}
        {task.checklist.length > 0 && (
          <span className="badge"><ListChecks size={14} />{checked}/{task.checklist.length}</span>
        )}
        {task.resources.length > 0 && (
          <span className="badge"><Link2 size={14} />{task.resources.length}</span>
        )}
      </span>
      {regular ? (
        <>
          <span className="when tabular" aria-hidden="true">
            <span className="t">{task.start}</span>
            <span className="track"><DurPill minutes={duration} /></span>
            <span className="t">{end}</span>
          </span>
          <span className="ruler" aria-hidden="true" style={{ "--progress": elapsedShare(task.start, task.duration_min, now) } as CSSProperties} />
        </>
      ) : (
        <span className="meta tabular" aria-hidden="true">
          {task.start && <span>{task.start}{end ? `–${end}` : ""}</span>}
          {duration > 0 && <DurPill minutes={duration} />}
          <span className="kind">{kind.label}</span>
        </span>
      )}
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
      <div className="empty-day glass-regular">
        <CalendarPlus size={44} strokeWidth={1.5} aria-hidden="true" />
        <h2>Nothing planned</h2>
        <p>Import a plan file or ask the agent to plan this day.</p>
        <button className="btn btn-filled" onClick={onImport}>Import a plan</button>
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
          <span className="free-label tabular">Free · {formatDuration(gap)}</span>
        </motion.li>,
      );
    }
    rows.push(
      <motion.li key={task.id} className="slot" layout transition={layoutSpring} {...enterExit}>
        <TaskCard task={task} onOpen={onOpen} now={isToday ? now : null} />
      </motion.li>,
    );
  });
  if (nowIndex === -1) rows.push(nowLine);

  return (
    <section className="timeline glass-regular" aria-label="Timeline">
      {anytime.length > 0 && (
        <div className="anytime">
          <h2 className="group-title">Anytime</h2>
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
