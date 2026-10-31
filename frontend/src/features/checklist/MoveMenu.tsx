import { CalendarArrowUp, CalendarDays, CalendarX2, Sun, Sunrise } from "lucide-react";
import { useState } from "react";

import { moveTask } from "../../app/taskActions";
import { Popover } from "../../components/primitives";
import type { Task } from "../../lib/api";
import { addDays, nextMonday, shortDay, today } from "../../lib/dates";

/** "Move to…" menu: Today, Tomorrow, Next week, a picked date, or Unscheduled. */
export function MoveMenu({ task, align = "end" }: { task: Task; align?: "start" | "end" }) {
  const [picking, setPicking] = useState(false);
  const now = today();
  const base = task.date && task.date > now ? task.date : now;
  const options = [
    task.date !== now && { label: "Today", hint: "", date: now, icon: Sun },
    { label: "Tomorrow", hint: shortDay(addDays(base, 1)), date: addDays(base, 1), icon: Sunrise },
    { label: "Next week", hint: shortDay(nextMonday(base)), date: nextMonday(base), icon: CalendarArrowUp },
  ].filter(Boolean) as { label: string; hint: string; date: string; icon: typeof Sun }[];

  return (
    <Popover
      label={`Move “${task.title}”`}
      align={align}
      trigger={({ open, toggle }) => (
        <button className="icon-btn" aria-label={`Move “${task.title}”`} aria-haspopup="dialog" aria-expanded={open} onClick={() => { setPicking(false); toggle(); }}>
          <CalendarDays size={18} strokeWidth={1.75} />
        </button>
      )}
    >
      {(close) => (
        <div className="menu">
          {options.map(({ label, hint, date, icon: Icon }) => (
            <button key={label} className="menu-item" onClick={() => { close(); void moveTask(task, date); }}>
              <Icon size={16} strokeWidth={1.75} />
              {label}
              <span className="hint">{hint}</span>
            </button>
          ))}
          {picking ? (
            <input
              className="field"
              type="date"
              autoFocus
              aria-label="Pick a date"
              defaultValue={task.date ?? now}
              onChange={(e) => {
                if (e.target.value) {
                  close();
                  void moveTask(task, e.target.value);
                }
              }}
            />
          ) : (
            <button className="menu-item" onClick={() => setPicking(true)}>
              <CalendarDays size={16} strokeWidth={1.75} />
              Pick a date…
            </button>
          )}
          {task.date && (
            <>
              <div className="menu-separator" />
              <button className="menu-item" onClick={() => { close(); void moveTask(task, null); }}>
                <CalendarX2 size={16} strokeWidth={1.75} />
                Remove date
              </button>
            </>
          )}
        </div>
      )}
    </Popover>
  );
}
