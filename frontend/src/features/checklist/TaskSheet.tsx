import { ArrowUpRight, BookOpen, FileText, Link2, PlayCircle, Sparkles, StickyNote, X } from "lucide-react";
import type { CSSProperties } from "react";

import { useTask } from "../../app/queries";
import { toggleChecklistItem, toggleDone } from "../../app/taskActions";
import { Checkbox, DurPill, Sheet } from "../../components/primitives";
import { dayMonth, elapsedShare, endTime, nowMinutes, relativeDay, today, weekdayLong } from "../../lib/dates";
import { typeOf } from "../../lib/taskTypes";
import { useAgent } from "../chat/agentStore";
import { MoveMenu } from "./MoveMenu";

import "./checklist.css";

const RESOURCE_ICONS = { video: PlayCircle, book: BookOpen, doc: FileText, article: FileText, note: StickyNote, link: Link2 };
const NEARBY = new Set(["Today", "Tomorrow", "Yesterday"]);

export function TaskSheet({ taskId, onClose, onAskAgent }: { taskId: number | null; onClose: () => void; onAskAgent: () => void }) {
  const { data: task } = useTask(taskId);
  const send = useAgent((s) => s.send);
  const running = useAgent((s) => s.running);

  if (!task) return <Sheet open={false} onClose={onClose} title="Task">{null}</Sheet>;
  const kind = typeOf(task.type);
  const Icon = kind.icon;
  const done = task.status === "done";
  const end = task.start ? endTime(task.start, task.duration_min) : null;
  const near = task.date ? relativeDay(task.date) : null;
  const dateNote = task.date ? (NEARBY.has(near!) ? near : dayMonth(task.date)) : null;
  const progress = task.date === today() ? elapsedShare(task.start, task.duration_min, nowMinutes()) : 0;

  const askForResources = () => {
    send(`Find good resources for #${task.id} "${task.title}" and save the best ones to it.`);
    onAskAgent();
    onClose();
  };

  return (
    <Sheet open={taskId !== null} onClose={onClose} title={task.title}>
      <div className="task-sheet" style={{ "--tint": kind.color } as CSSProperties}>
        <header className="sheet-header">
          <span className="sheet-glyph" aria-hidden="true"><Icon size={20} strokeWidth={2} /></span>
          <h2>{task.title}</h2>
          <button className="icon-btn secondary" aria-label="Close" onClick={onClose}><X size={20} /></button>
        </header>

        {/* the reference's "Mondays" card: day, kind, Start/End numerals, duration pill, tick ruler */}
        <div className="time-card tabular">
          <div className="head">
            <span className="day">
              {task.date ? weekdayLong(task.date) : "Unscheduled"}
              {dateNote && <span className="date"> · {dateNote}</span>}
            </span>
            <span className="kind"><Icon size={12} strokeWidth={2.25} aria-hidden="true" />{kind.label}</span>
          </div>
          {task.start ? (
            <>
              <div className="labels" aria-hidden="true"><span>Start</span>{end && <span>End</span>}</div>
              <div className="when">
                <span className="t"><span className="visually-hidden">Starts </span>{task.start}</span>
                <span className="track">{task.duration_min ? <DurPill minutes={task.duration_min} /> : null}</span>
                {end ? <span className="t"><span className="visually-hidden">ends </span>{end}</span> : <span />}
              </div>
            </>
          ) : task.duration_min ? (
            <div className="when only"><DurPill minutes={task.duration_min} /><span className="muted-inline">Anytime</span></div>
          ) : (
            <p className="muted-inline">Anytime</p>
          )}
          <span className="ruler" aria-hidden="true" style={{ "--progress": progress } as CSSProperties} />
        </div>

        <dl className="facts tabular">
          <div><dt>Type</dt><dd>{kind.label}</dd></div>
          <div><dt>Priority</dt><dd className="cap">{task.priority}</dd></div>
          {task.tags.length > 0 && <div><dt>Tags</dt><dd>{task.tags.map((t) => <span key={t} className="chip">#{t}</span>)}</dd></div>}
        </dl>

        {task.notes && <p className="notes">{task.notes}</p>}

        {task.checklist.length > 0 && (
          <section>
            <h3 className="group-title">Steps</h3>
            <ul className="group">
              {task.checklist.map((item) => (
                <li key={item.id} className="step-row" data-done={item.done || undefined}>
                  <Checkbox size="sm" checked={item.done} color={kind.color} label={item.title}
                    onChange={(checked) => void toggleChecklistItem(item.id, checked)} />
                  <span>{item.title}</span>
                </li>
              ))}
            </ul>
          </section>
        )}

        <section>
          <h3 className="group-title">Resources</h3>
          {task.resources.length > 0 ? (
            <ul className="group">
              {task.resources.map((r) => {
                const RIcon = RESOURCE_ICONS[r.kind as keyof typeof RESOURCE_ICONS] ?? Link2;
                return (
                  <li key={r.id} className="resource-row">
                    <RIcon size={18} strokeWidth={1.75} aria-hidden="true" />
                    <span className="resource-text">
                      {r.url ? (
                        <a href={r.url} target="_blank" rel="noreferrer">
                          {r.title}
                          <ArrowUpRight size={14} strokeWidth={2} aria-hidden="true" />
                        </a>
                      ) : (
                        <span>{r.title}</span>
                      )}
                      {(r.note || r.added_by === "agent") && (
                        <span className="resource-note">{r.added_by === "agent" ? "Found by the agent" : ""}{r.note && r.added_by === "agent" ? " · " : ""}{r.note}</span>
                      )}
                    </span>
                  </li>
                );
              })}
            </ul>
          ) : (
            <p className="muted">No resources yet.</p>
          )}
          <button className="btn btn-tinted ask" onClick={askForResources} disabled={running}>
            <Sparkles size={16} strokeWidth={2} /> Ask the agent for resources
          </button>
        </section>

        <footer className="sheet-footer">
          <MoveMenu task={task} align="start" />
          <button className={`btn ${done ? "btn-tinted" : "btn-filled"} btn-large`} onClick={() => void toggleDone(task)}>
            {done ? "Reopen" : "Mark as done"}
          </button>
        </footer>
      </div>
    </Sheet>
  );
}
