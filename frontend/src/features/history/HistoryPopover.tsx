import { Download, FileUp, History, Sparkles, User } from "lucide-react";

import { useHistory } from "../../app/queries";
import { undo } from "../../app/taskActions";
import { Popover } from "../../components/primitives";
import type { ChangeSet } from "../../lib/api";
import { useReducedTransparency } from "../../design/transparency";
import { timeAgo } from "../../lib/dates";

import "./history.css";

const ACTOR_ICON = { user: User, agent: Sparkles, import: FileUp };

function Entries({ onUndo }: { onUndo: () => void }) {
  const { data, isLoading } = useHistory(true);
  if (isLoading) return <p className="history-empty">Loading…</p>;
  if (!data?.length) return <p className="history-empty">Changes you, the agent and imports make will appear here.</p>;
  const undoneTargets = new Set(data.filter((c) => c.undo_of).map((c) => c.undo_of));
  return (
    <ol className="history-list">
      {data.map((cs: ChangeSet) => {
        const Icon = ACTOR_ICON[cs.actor] ?? User;
        const canUndo = !cs.undone_at && !cs.undo_of && !undoneTargets.has(cs.id);
        return (
          <li key={cs.id} className="history-item" data-undone={cs.undone_at ? true : undefined}>
            <Icon size={16} strokeWidth={1.75} aria-label={cs.actor} />
            <span className="history-text">
              <span className="history-summary">{cs.summary}</span>
              <span className="history-time">{timeAgo(cs.created_at)}{cs.undone_at ? " · undone" : ""}</span>
            </span>
            {canUndo && (
              <button className="btn btn-plain" onClick={() => { onUndo(); void undo(cs.id); }}>Undo</button>
            )}
          </li>
        );
      })}
    </ol>
  );
}

/** Safari has no prefers-reduced-transparency, so the app offers the switch itself. */
function TransparencySetting() {
  const [reduced, setReduced] = useReducedTransparency();
  return (
    <label className="history-setting">
      <span>Reduce transparency</span>
      <input className="switch" type="checkbox" checked={reduced} onChange={(e) => setReduced(e.target.checked)} />
    </label>
  );
}

export function HistoryPopover() {
  return (
    <Popover
      label="History"
      trigger={({ open, toggle }) => (
        <button className="icon-btn ornament" aria-label="History" aria-expanded={open} onClick={toggle}>
          <History size={20} strokeWidth={1.75} />
        </button>
      )}
    >
      {(close) => (
        <div className="history">
          <div className="history-head">
            <h3>History</h3>
            <a className="btn btn-plain" href="/api/export" download>
              <Download size={15} strokeWidth={2} /> Export
            </a>
          </div>
          <Entries onUndo={close} />
          <TransparencySetting />
        </div>
      )}
    </Popover>
  );
}
