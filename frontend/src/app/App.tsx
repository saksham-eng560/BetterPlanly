import { Plus, Sparkles } from "lucide-react";
import { useEffect, useMemo, useState } from "react";

import { Toaster } from "../components/toasts";
import { ChatPanel } from "../features/chat/ChatPanel";
import { useAgent } from "../features/chat/agentStore";
import { Checklist } from "../features/checklist/Checklist";
import { TaskSheet } from "../features/checklist/TaskSheet";
import { HistoryPopover } from "../features/history/HistoryPopover";
import { ImportSheet } from "../features/import/ImportSheet";
import { DayTimeline } from "../features/timeline/DayTimeline";
import { WeekStrip } from "../features/timeline/WeekStrip";
import type { Task } from "../lib/api";
import { dayMonth, relativeDay, today as todayIso, weekStart, weekdayLong } from "../lib/dates";
import { useAppState, useMissed, useUnscheduled, useWeekTasks } from "./queries";

import "./app.css";

const REVIEW_KEY = "planly:last-day-review";

/** First open of a day with missed tasks → let the agent re-plan them (FR-4.4). */
function useDayReview(today: string, missedCount: number | undefined) {
  const dayReview = useAgent((s) => s.dayReview);
  useEffect(() => {
    if (!missedCount) return;
    try {
      if (localStorage.getItem(REVIEW_KEY) === today) return;
      localStorage.setItem(REVIEW_KEY, today);
    } catch {
      return; // no storage: don't risk reviewing on every load
    }
    dayReview();
  }, [today, missedCount, dayReview]);
}

export function App() {
  const today = todayIso();
  const [selected, setSelected] = useState(today);
  const [openTask, setOpenTask] = useState<number | null>(null);
  const [importOpen, setImportOpen] = useState(false);
  const [chatOpen, setChatOpen] = useState(false); // narrow screens only

  const week = weekStart(selected);
  const weekTasks = useWeekTasks(week);
  const missed = useMissed(today);
  const unscheduled = useUnscheduled();
  const state = useAppState(today);
  const running = useAgent((s) => s.running);
  useDayReview(today, missed.data?.length);

  const dayTasks = useMemo(
    () => (weekTasks.data ?? []).filter((t) => t.date === selected),
    [weekTasks.data, selected],
  );
  const isToday = selected === today;
  const done = dayTasks.filter((t) => t.status === "done").length;
  const open = (task: Task) => setOpenTask(task.id);

  return (
    <div className="app" data-chat-open={chatOpen || undefined}>
      <div className="main-column">
        <header className="toolbar material">
          <div className="toolbar-inner">
            <span className="brand">Planly</span>
            <WeekStrip weekStart={week} selected={selected} today={today} tasks={weekTasks.data ?? []} onSelect={setSelected} />
            <div className="toolbar-actions">
              {!isToday && <button className="btn btn-gray" onClick={() => setSelected(today)}>Today</button>}
              <HistoryPopover />
              <button className="btn btn-tinted" aria-label="Import" onClick={() => setImportOpen(true)}>
                <Plus size={16} strokeWidth={2.25} /> <span className="btn-label">Import</span>
              </button>
              <button
                className="icon-btn chat-toggle"
                aria-label="Open the agent"
                aria-pressed={chatOpen}
                onClick={() => setChatOpen((o) => !o)}
              >
                <Sparkles size={20} strokeWidth={1.75} />
                {running && <span className="activity-dot" />}
              </button>
            </div>
          </div>
        </header>

        <main className="content">
          <div className="day-head">
            <h1>{isToday ? "Today" : weekdayLong(selected)}</h1>
            <p className="tabular">
              {isToday ? `${weekdayLong(selected)}, ${dayMonth(selected)}` : dayMonth(selected)}
              {dayTasks.length > 0 && ` · ${done} of ${dayTasks.length} done`}
            </p>
          </div>

          {weekTasks.isLoading ? (
            <div className="skeleton" aria-hidden="true"><span /><span /><span /></div>
          ) : weekTasks.isError ? (
            <p className="load-error" role="alert">Can't reach the Planly backend. Is it running on port 8000?</p>
          ) : (
            <DayTimeline tasks={dayTasks} isToday={isToday} onOpen={open} onImport={() => setImportOpen(true)} />
          )}

          <Checklist
            dayLabel={relativeDay(selected, today)}
            dayTasks={dayTasks}
            missed={isToday ? missed.data ?? [] : []}
            unscheduled={unscheduled.data ?? []}
            onOpen={open}
          />
        </main>
      </div>

      <div className="inspector">
        <ChatPanel state={state.data} onClose={chatOpen ? () => setChatOpen(false) : undefined} />
      </div>
      <div className="scrim" onClick={() => setChatOpen(false)} aria-hidden="true" />

      <TaskSheet taskId={openTask} onClose={() => setOpenTask(null)} onAskAgent={() => setChatOpen(true)} />
      <ImportSheet open={importOpen} onClose={() => setImportOpen(false)} notionConfigured={state.data?.notion_configured ?? false} />
      <Toaster />
    </div>
  );
}
