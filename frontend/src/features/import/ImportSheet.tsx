import { Check, Copy, Database, FileUp, Sparkles, X } from "lucide-react";
import { motion } from "motion/react";
import { useRef, useState } from "react";

import agentPrompt from "../../../../examples/AGENT_PROMPT.md?raw";
import { refreshPlan } from "../../app/queryClient";
import { undo } from "../../app/taskActions";
import { Sheet } from "../../components/primitives";
import { toast } from "../../components/toasts";
import { ApiError, type ImportResult, api } from "../../lib/api";

import { type PickedFile, filesFromDrop, filesFromList } from "./collectFiles";

import "./import.css";

type Tab = "file" | "notion" | "prompt";

const TABS = [["file", "Plan file", FileUp], ["notion", "Notion", Database], ["prompt", "Agent prompt", Sparkles]] as const;
const underlineSpring = { type: "spring", duration: 0.25, bounce: 0 } as const;

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
  const folderInput = useRef<HTMLInputElement>(null);

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

  const upload = (files: PickedFile[]) => {
    if (!files.length) {
      setErrors(["No plan files there. Drop the .zip from Notion, or the folder it was unzipped into."]);
      return;
    }
    return run(() => api.importFiles(files));
  };

  return (
    <Sheet open={open} onClose={onClose} title="Import tasks" wide>
      <header className="sheet-header">
        <h2>Import tasks</h2>
        <button className="icon-btn secondary" aria-label="Close" onClick={onClose}><X size={20} /></button>
      </header>

      <div className="segmented" role="tablist" aria-label="Import source">
        {TABS.map(([id, label, Icon]) => (
          <button key={id} role="tab" aria-selected={tab === id} onClick={() => { setTab(id); setErrors([]); setResult(null); }}>
            {tab === id && <motion.span layoutId="tab-underline" className="tab-underline" transition={underlineSpring} aria-hidden="true" />}
            <Icon size={16} strokeWidth={1.75} aria-hidden="true" />
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
              onDrop={async (e) => {
                e.preventDefault();
                setDragging(false);
                await upload(await filesFromDrop(e.dataTransfer));
              }}
            >
              <FileUp size={36} strokeWidth={1.5} aria-hidden="true" />
              <p className="drop-title">Drop your Notion export here</p>
              <p className="drop-hint">
                The .zip, or the folder your Mac unzipped it into. Single pages (.md), Notion CSVs and Planly JSON/YAML plans work too.
              </p>
              <div className="drop-actions">
                <button className="btn btn-filled" disabled={busy} onClick={() => folderInput.current?.click()}>
                  {busy ? "Importing…" : "Choose Folder…"}
                </button>
                <button className="btn btn-tinted" disabled={busy} onClick={() => input.current?.click()}>
                  Choose Files…
                </button>
              </div>
              <input
                ref={input}
                type="file"
                hidden
                multiple
                aria-label="Plan files"
                accept=".zip,.json,.yaml,.yml,.md,.markdown,.csv"
                onChange={(e) => { void upload(filesFromList(e.target.files)); e.target.value = ""; }}
              />
              <input
                ref={folderInput}
                type="file"
                hidden
                aria-label="Exported folder"
                {...{ webkitdirectory: "", directory: "" }}
                onChange={(e) => { void upload(filesFromList(e.target.files)); e.target.value = ""; }}
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
              {copied ? <Check size={16} strokeWidth={2.5} className="copied" /> : <Copy size={16} strokeWidth={2} />}
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
