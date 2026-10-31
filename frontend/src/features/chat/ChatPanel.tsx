import { ArrowUp, CircleCheck, LoaderCircle, Sparkles, TriangleAlert, Undo2, X } from "lucide-react";
import { AnimatePresence, motion } from "motion/react";
import { type FormEvent, useEffect, useRef, useState } from "react";

import { undo } from "../../app/taskActions";
import type { AppState } from "../../lib/api";
import { type ChatItem, describeTool, useAgent } from "./agentStore";

import "./chat.css";

const SUGGESTIONS = [
  "I'm behind — re-plan the rest of today",
  "What should I focus on next?",
  "How did this week go?",
];

/** Trigger messages carry instructions for the model; the chat shows only what happened. */
function eventSummary(text: string): string {
  return text
    .replace(/^\[(update|day review)\]\s*/, "")
    .replace(/\s*(Adjust the rest of today|Bring the missed tasks)[\s\S]*$/, "")
    .replace(/\.$/, "");
}

function Item({ item }: { item: ChatItem }) {
  switch (item.kind) {
    case "user":
      return <div className="bubble user">{item.text}</div>;
    case "assistant":
      return <div className="bubble assistant">{item.text}</div>;
    case "event":
      return <div className="event-chip" title={item.text}><span>{eventSummary(item.text)}</span></div>;
    case "error":
      return (
        <div className="chat-error" role="alert">
          <TriangleAlert size={16} strokeWidth={2} aria-hidden="true" /> {item.text}
        </div>
      );
    case "tool":
      return (
        <div className="tool-row" data-done={item.done || undefined}>
          {item.done ? <CircleCheck size={14} strokeWidth={2} /> : <LoaderCircle size={14} strokeWidth={2} className="spin" />}
          {describeTool(item.name, item.args)}
        </div>
      );
    case "changes": {
      const live = item.changes.filter((c) => !c.undone);
      return (
        <div className="changes-card">
          <div className="changes-head">
            <span>{item.changes.length === 1 ? "1 change" : `${item.changes.length} changes`}</span>
            {live.length > 0 && (
              <button className="btn btn-plain" onClick={async () => { for (const c of [...live].reverse()) await undo(c.id); }}>
                <Undo2 size={15} strokeWidth={2} /> Undo
              </button>
            )}
          </div>
          <ul>
            {item.changes.map((c) => (
              <li key={c.id} data-undone={c.undone || undefined}>{c.summary}</li>
            ))}
          </ul>
        </div>
      );
    }
  }
}

export function ChatPanel({ state, onClose }: { state: AppState | undefined; onClose?: () => void }) {
  const { items, running, load, send, reactToChanges, setReactToChanges } = useAgent();
  const [draft, setDraft] = useState("");
  const scroller = useRef<HTMLDivElement>(null);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    const el = scroller.current;
    if (el) el.scrollTo({ top: el.scrollHeight, behavior: items.length > 1 ? "smooth" : "auto" });
  }, [items]);

  const submit = (e?: FormEvent) => {
    e?.preventDefault();
    if (!draft.trim()) return;
    send(draft);
    setDraft("");
  };

  const reachable = state?.agent.reachable;
  return (
    <aside className="chat glass-regular" aria-label="Planly agent">
      <header className="chat-head">
        <div className="chat-title">
          <Sparkles size={18} strokeWidth={2} aria-hidden="true" />
          <div>
            <h2>Agent</h2>
            <p className="chat-status">
              <span className="status-dot" data-on={reachable || undefined} />
              {state ? `${state.agent.model}${reachable ? "" : " · offline"}` : "Connecting…"}
            </p>
          </div>
        </div>
        <label className="react-toggle">
          <span>React to ticks</span>
          <input className="switch" type="checkbox" role="switch" checked={reactToChanges} onChange={(e) => setReactToChanges(e.target.checked)} />
        </label>
        {onClose && (
          <button className="icon-btn secondary" aria-label="Close agent" data-drawer-close onClick={onClose}><X size={20} /></button>
        )}
      </header>

      <div className="chat-scroll" ref={scroller}>
        {items.length === 0 ? (
          <div className="chat-empty">
            <Sparkles size={32} strokeWidth={1.5} aria-hidden="true" />
            <p>Tick tasks and I'll adjust the rest of your day. Or ask me anything about your plan.</p>
            <div className="suggestions">
              {SUGGESTIONS.map((s) => (
                <button key={s} className="btn btn-gray" onClick={() => send(s)}>{s}</button>
              ))}
            </div>
          </div>
        ) : (
          <ol className="chat-items" aria-live="polite">
            <AnimatePresence initial={false}>
              {items.map((item) => (
                <motion.li
                  key={item.id}
                  className={`chat-item ${item.kind}`}
                  initial={{ opacity: 0, transform: "translateY(6px)" }}
                  animate={{ opacity: 1, transform: "translateY(0px)" }}
                  transition={{ duration: 0.2, ease: [0.23, 1, 0.32, 1] }}
                >
                  <Item item={item} />
                </motion.li>
              ))}
            </AnimatePresence>
            {running && items.at(-1)?.kind !== "assistant" && (
              <li className="chat-item"><div className="typing" aria-label="The agent is thinking"><span /><span /><span /></div></li>
            )}
          </ol>
        )}
      </div>

      <form className="composer" onSubmit={submit}>
        <textarea
          className="field"
          rows={1}
          placeholder="Ask your agent…"
          aria-label="Message the agent"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) submit(e);
          }}
        />
        <button className="send" type="submit" aria-label="Send" disabled={!draft.trim()}>
          <ArrowUp size={18} strokeWidth={2.5} />
        </button>
      </form>
    </aside>
  );
}
