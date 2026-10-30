import { AnimatePresence, motion } from "motion/react";
import { useEffect, useRef } from "react";
import { create } from "zustand";

import "./toasts.css";

interface Toast {
  id: number;
  message: string;
  action?: { label: string; run: () => void };
  tone?: "error";
}

interface ToastStore {
  toasts: Toast[];
  show: (toast: Omit<Toast, "id">) => void;
  dismiss: (id: number) => void;
}

let nextId = 1;

export const useToasts = create<ToastStore>((set) => ({
  toasts: [],
  show: (toast) => set((s) => ({ toasts: [...s.toasts.slice(-2), { ...toast, id: nextId++ }] })),
  dismiss: (id) => set((s) => ({ toasts: s.toasts.filter((t) => t.id !== id) })),
}));

export const toast = (toast: Omit<Toast, "id">) => useToasts.getState().show(toast);

const LIFETIME_MS = 5000;

function ToastPill({ toast }: { toast: Toast }) {
  const dismiss = useToasts((s) => s.dismiss);
  const timer = useRef<number | undefined>(undefined);
  const start = () => {
    timer.current = window.setTimeout(() => dismiss(toast.id), LIFETIME_MS);
  };
  const stop = () => window.clearTimeout(timer.current);

  useEffect(() => {
    start();
    const onVisibility = () => (document.hidden ? stop() : start());
    document.addEventListener("visibilitychange", onVisibility);
    return () => {
      stop();
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, []);

  return (
    <motion.div
      layout
      className={`toast material-thick${toast.tone === "error" ? " error" : ""}`}
      role="status"
      initial={{ opacity: 0, transform: "translateY(100%) scale(0.96)" }}
      animate={{ opacity: 1, transform: "translateY(0%) scale(1)" }}
      exit={{ opacity: 0, transform: "translateY(30%) scale(0.98)", transition: { duration: 0.15 } }}
      transition={{ type: "spring", duration: 0.4, bounce: 0.15 }}
      onPointerEnter={stop}
      onPointerLeave={start}
    >
      <span className="toast-message">{toast.message}</span>
      {toast.action && (
        <button
          className="btn btn-plain"
          onClick={() => {
            toast.action!.run();
            dismiss(toast.id);
          }}
        >
          {toast.action.label}
        </button>
      )}
    </motion.div>
  );
}

export function Toaster() {
  const toasts = useToasts((s) => s.toasts);
  return (
    <div className="toaster" aria-live="polite">
      <AnimatePresence initial={false}>
        {toasts.map((t) => (
          <ToastPill key={t.id} toast={t} />
        ))}
      </AnimatePresence>
    </div>
  );
}
