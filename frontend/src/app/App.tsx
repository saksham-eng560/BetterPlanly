import { Plus, Sparkles } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";

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
import { dayMonth, today as todayIso, weekStart, weekdayLong } from "../lib/dates";
import { useAppState, useMissed, useTaskRange, useUnscheduled, useWeekTasks } from "./queries";

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

const DRAWER_QUERY = "(max-width: 1080px)"; // keep in step with app.css

/** True while the agent is a drawer over the page (narrow windows) rather than a side window. */
function useDrawerLayout() {
  const [narrow, setNarrow] = useState(() => window.matchMedia(DRAWER_QUERY).matches);
  useEffect(() => {
    const query = window.matchMedia(DRAWER_QUERY);
    const update = () => setNarrow(query.matches);
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, []);
  return narrow;
}

export function App() {
  const today = todayIso();
  const [selected, setSelected] = useState(today);
  const [openTask, setOpenTask] = useState<number | null>(null);
  const [importOpen, setImportOpen] = useState(false);
  const [chatOpen, setChatOpen] = useState(false); // narrow screens only

  const week = weekStart(selected);
  const weekTasks = useWeekTasks(week);
  const boxTasks = useTaskRange(week, 14);
  const missed = useMissed(today);
  const unscheduled = useUnscheduled();
  const state = useAppState(today);
  const running = useAgent((s) => s.running);
  useDayReview(today, missed.data?.length);

  // the open drawer is modal: the page behind it is inert, focus starts on its Close button and
  // goes back to the toggle when it closes (Close, Escape or the scrim)
  const drawerOpen = useDrawerLayout() && chatOpen;
  const toggleRef = useRef<HTMLButtonElement>(null);
  const inspectorRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!drawerOpen) return;
    const drawer = inspectorRef.current;
    const frame = requestAnimationFrame(() => drawer?.querySelector<HTMLElement>("[data-drawer-close]")?.focus());
    const onKey = (e: KeyboardEvent) => {
      // a sheet or menu on top gets Escape first
      if (e.key === "Escape" && !e.defaultPrevented && !document.querySelector("dialog[open]")) setChatOpen(false);
    };
    document.addEventListener("keydown", onKey);
    return () => {
      cancelAnimationFrame(frame);
      document.removeEventListener("keydown", onKey);
      const active = document.activeElement;
      if (!active || active === document.body || drawer?.contains(active)) toggleRef.current?.focus();
    };
  }, [drawerOpen]);

  const dayTasks = useMemo(
    () => (weekTasks.data ?? []).filter((t) => t.date === selected),
    [weekTasks.data, selected],
  );
  const isToday = selected === today;
  const done = dayTasks.filter((t) => t.status === "done").length;
  const open = (task: Task) => setOpenTask(task.id);

  return (
    <div className="app" data-chat-open={chatOpen || undefined}>
      <div className="main-column" inert={drawerOpen || undefined}>
        <header className="toolbar">
          <div className="toolbar-inner">
            <span className="brand">Planly</span>
            <WeekStrip weekStart={week} selected={selected} today={today} tasks={weekTasks.data ?? []} onSelect={setSelected} />
            <div className="toolbar-actions">
              <HistoryPopover />
              <button className="btn btn-filled import-btn" aria-label="Import" onClick={() => setImportOpen(true)}>
                <Plus size={16} strokeWidth={2.5} /> <span className="btn-label">Import</span>
              </button>
              <button
                ref={toggleRef}
                className="icon-btn ornament chat-toggle"
                aria-label="Open the agent"
                aria-expanded={drawerOpen}
                aria-controls="agent"
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
            <div className="day-title">
              <h1>{isToday ? "Today" : weekdayLong(selected)}</h1>
              {!isToday && <button className="btn today-btn ornament" onClick={() => setSelected(today)}>Today</button>}
            </div>
            <p className="tabular">
              {isToday ? `${weekdayLong(selected)}, ${dayMonth(selected)}` : dayMonth(selected)}
              {dayTasks.length > 0 && ` · ${done} of ${dayTasks.length} done`}
            </p>
          </div>

          {weekTasks.isLoading ? (
            <div className="skeleton glass-regular" aria-hidden="true"><span /><span /><span /></div>
          ) : weekTasks.isError ? (
            <p className="load-error glass-regular" role="alert">Can't reach the Planly backend. Is it running on port 8000?</p>
          ) : (
            <DayTimeline tasks={dayTasks} isToday={isToday} onOpen={open} onImport={() => setImportOpen(true)} />
          )}

          <Checklist
            tasks={boxTasks.data ?? []}
            missed={missed.data ?? []}
            unscheduled={unscheduled.data ?? []}
            today={today}
            onOpen={open}
          />
        </main>
      </div>

      <div id="agent" className="inspector" ref={inspectorRef}>
        <ChatPanel state={state.data} onClose={drawerOpen ? () => setChatOpen(false) : undefined} />
      </div>
      <div className="scrim" onClick={() => setChatOpen(false)} aria-hidden="true" />

      <TaskSheet taskId={openTask} onClose={() => setOpenTask(null)} onAskAgent={() => setChatOpen(true)} />
      <ImportSheet open={importOpen} onClose={() => setImportOpen(false)} notionConfigured={state.data?.notion_configured ?? false} />
      <Toaster />
    </div>
  );
}
