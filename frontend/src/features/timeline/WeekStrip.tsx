import { ChevronLeft, ChevronRight } from "lucide-react";
import { motion } from "motion/react";

import type { Task } from "../../lib/api";
import { addDays, parseDate } from "../../lib/dates";

import "./timeline.css";

const lozengeSpring = { type: "spring", duration: 0.3, bounce: 0 } as const;

export function WeekStrip({
  weekStart,
  selected,
  today,
  tasks,
  onSelect,
}: {
  weekStart: string;
  selected: string;
  today: string;
  tasks: Task[];
  onSelect: (iso: string) => void;
}) {
  const days = Array.from({ length: 7 }, (_, i) => addDays(weekStart, i));
  const busy = new Set(tasks.filter((t) => t.status !== "done").map((t) => t.date));

  return (
    <nav className="week-strip ornament" aria-label="Choose a day">
      <button className="icon-btn secondary" aria-label="Previous week" onClick={() => onSelect(addDays(selected, -7))}>
        <ChevronLeft size={18} strokeWidth={2} />
      </button>
      <ol>
        {days.map((iso) => {
          const d = parseDate(iso);
          const isSelected = iso === selected;
          return (
            <li key={iso}>
              <button
                className="day"
                aria-pressed={isSelected}
                aria-current={iso === today ? "date" : undefined}
                data-today={iso === today || undefined}
                aria-label={d.toLocaleDateString(undefined, { weekday: "long", day: "numeric", month: "long" })}
                onClick={() => onSelect(iso)}
              >
                {/* the selected-day lozenge slides between days, like the reference's nav pill */}
                {isSelected && <motion.span layoutId="day-lozenge" className="lozenge" transition={lozengeSpring} aria-hidden="true" />}
                <span className="dow">{d.toLocaleDateString(undefined, { weekday: "narrow" })}</span>
                <span className="num tabular">{d.getDate()}</span>
                <span className="dot" data-on={busy.has(iso) || undefined} />
              </button>
            </li>
          );
        })}
      </ol>
      <button className="icon-btn secondary" aria-label="Next week" onClick={() => onSelect(addDays(selected, 7))}>
        <ChevronRight size={18} strokeWidth={2} />
      </button>
    </nav>
  );
}
