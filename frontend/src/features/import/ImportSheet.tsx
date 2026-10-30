import { Check, Copy, FileUp, X } from "lucide-react";
import { useRef, useState } from "react";

import agentPrompt from "../../../../examples/AGENT_PROMPT.md?raw";
import { refreshPlan } from "../../app/queryClient";
import { undo } from "../../app/taskActions";
import { Sheet } from "../../components/primitives";
import { toast } from "../../components/toasts";
import { ApiError, type ImportResult, api } from "../../lib/api";

import "./import.css";

type Tab = "file" | "notion" | "prompt";

function Result({ result }: { result: ImportResult }) {
  return (
    <div className="import-result" role="status">
      <Check size={18} strokeWidth={2.5} aria-hidden="true" />
      <span>
        <strong>{result.plans.length > 1 ? `${result.plans.length} pages` : result.plan.title}</strong>:{" "}
        {result.created} new, {result.updated} updated
        {result.unchanged ? `, ${result.unchanged} unchanged` : ""}
        {result.skipped.length > 0 && (
          <span className="import-skipped"> · skipped {result.skipped.length} without tasks</span>
        )}
      </span>
    </div>
  );
}

export function ImportSheet({ open, onClose, notionConfigured }: { open: boolean; onClose: () => void; notionConfigured: boolean }) {
  const [tab, setTab] = useState<Tab>("file");
  const [busy, setBusy] = useState(false);
  const [dragging, setDragging] = useState(false);
  const [result, setResult] = useState<ImportResult | null>(null);
  const [errors, setErrors] = useState<string[]>([]);
  const [copied, setCopied] = useState(false);
  const [databaseId, setDatabaseId] = useState("");
  const input = useRef<HTMLInputElement>(null);

  async function run(action: () => Promise<ImportResult>) {
    setBusy(true);
    setErrors([]);
    setResult(null);
    try {
      const imported = await action();
      setResult(imported);
      await refreshPlan();
      const changeSet = imported.change_set;
      toast({
        message: imported.plans.length > 1 ? `Imported ${imported.plans.length} pages` : `Imported “${imported.plan.title}”`,
        action: changeSet ? { label: "Undo", run: () => void undo(changeSet.id) } : undefined,
      });
    } catch (error) {
      setErrors(error instanceof ApiError ? [error.message, ...error.errors] : ["Import failed."]);
    } finally {
      setBusy(false);
    }
  }

  const upload = (file: File | undefined) => file && run(() => api.importFile(file));

  return (
    <Sheet open={open} onClose={onClose} title="Import tasks" wide>
      <header className="sheet-header">
        <h2>Import tasks</h2>
        <button className="icon-btn secondary" aria-label="Close" onClick={onClose}><X size={20} /></button>
      </header>

      <div className="segmented" role="tablist" aria-label="Import source">
        {([["file", "Plan file"], ["notion", "Notion"], ["prompt", "Agent prompt"]] as const).map(([id, label]) => (
          <button key={id} role="tab" aria-selected={tab === id} onClick={() => { setTab(id); setErrors([]); setResult(null); }}>
            {label}
          </button>
        ))}
      </div>

      <div className="import-pane">
        {tab === "file" && (
          <>
            <div
              className="drop-zone"
              data-dragging={dragging || undefined}
              onDragOver={(e) => { e.preventDefault(); setDragging(true); }}
              onDragLeave={() => setDragging(false)}
              onDrop={(e) => { e.preventDefault(); setDragging(false); void upload(e.dataTransfer.files[0]); }}
            >
              <FileUp size={36} strokeWidth={1.5} aria-hidden="true" />
              <p className="drop-title">Drop a plan file here</p>
              <p className="drop-hint">A whole Notion export (.zip), a Notion page (.md), a Notion CSV, or a Planly JSON/YAML plan</p>
              <button className="btn btn-filled" disabled={busy} onClick={() => input.current?.click()}>
                {busy ? "Importing…" : "Choose File…"}
              </button>
              <input
                ref={input}
                type="file"
                hidden
                accept=".zip,.json,.yaml,.yml,.md,.markdown,.csv"
                onChange={(e) => { void upload(e.target.files?.[0]); e.target.value = ""; }}
              />
            </div>
          </>
        )}

        {tab === "notion" && (
          <form className="notion-form" onSubmit={(e) => { e.preventDefault(); void run(() => api.importNotion(databaseId)); }}>
            <label htmlFor="notion-db" className="field-label">Database link or id</label>
            <input
              id="notion-db"
              className="field"
              placeholder="https://www.notion.so/…"
              value={databaseId}
              onChange={(e) => setDatabaseId(e.target.value)}
              disabled={!notionConfigured}
            />
            <p className="field-help">
              {notionConfigured
                ? "Share the database with your Notion integration first. Syncing again updates tasks instead of duplicating them."
                : "Notion isn't connected. Set NOTION_TOKEN for the backend (see docs/PLAN_FORMAT.md), or upload a CSV export under Plan file."}
            </p>
            <button className="btn btn-filled" type="submit" disabled={!notionConfigured || !databaseId.trim() || busy}>
              {busy ? "Syncing…" : "Sync from Notion"}
            </button>
          </form>
        )}

        {tab === "prompt" && (
          <div className="prompt-pane">
            <p className="field-help">
              Paste this into any AI assistant, describe your week, save its reply as <code>plan.json</code> and import it.
            </p>
            <pre className="prompt-preview">{agentPrompt}</pre>
            <button
              className="btn btn-tinted"
              onClick={async () => {
                await navigator.clipboard.writeText(agentPrompt);
                setCopied(true);
                window.setTimeout(() => setCopied(false), 1600);
              }}
            >
              {copied ? <Check size={16} strokeWidth={2.5} /> : <Copy size={16} strokeWidth={2} />}
              {copied ? "Copied" : "Copy prompt"}
            </button>
          </div>
        )}

        {result && <Result result={result} />}
        {errors.length > 0 && (
          <ul className="import-errors" role="alert">
            {errors.map((e) => <li key={e}>{e}</li>)}
          </ul>
        )}
      </div>
    </Sheet>
  );
}
