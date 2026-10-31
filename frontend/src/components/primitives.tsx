/** Small shared primitives: Reminders-style checkbox, anchored popover, native-dialog sheet. */

import { AnimatePresence, motion } from "motion/react";
import { type ReactNode, useEffect, useRef, useState } from "react";

import "./primitives.css";

export function Checkbox({
  checked,
  onChange,
  color = "var(--accent)",
  label,
  size = "md",
}: {
  checked: boolean;
  onChange: (checked: boolean) => void;
  color?: string;
  label: string;
  size?: "sm" | "md";
}) {
  return (
    <label className={`checkbox checkbox-${size}`} style={{ "--check": color } as React.CSSProperties}>
      <input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} aria-label={label} />
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <circle className="ring" cx="12" cy="12" r="10.25" />
        <circle className="fill" cx="12" cy="12" r="11" />
        <path className="mark" d="M7.5 12.4l3 3 6-6.6" />
      </svg>
    </label>
  );
}

export function Popover({
  trigger,
  children,
  align = "end",
  label,
}: {
  trigger: (props: { open: boolean; toggle: () => void }) => ReactNode;
  children: (close: () => void) => ReactNode;
  align?: "start" | "end";
  label: string;
}) {
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onPointer = (e: PointerEvent) => {
      if (!root.current?.contains(e.target as Node)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    document.addEventListener("pointerdown", onPointer);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("pointerdown", onPointer);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  return (
    <div className="popover-anchor" ref={root}>
      {trigger({ open, toggle: () => setOpen((o) => !o) })}
      <AnimatePresence>
        {open && (
          <motion.div
            role="dialog"
            aria-label={label}
            className={`popover material-thick popover-${align}`}
            initial={{ opacity: 0, transform: "scale(0.96)" }}
            animate={{ opacity: 1, transform: "scale(1)" }}
            exit={{ opacity: 0, transform: "scale(0.98)", transition: { duration: 0.12 } }}
            transition={{ duration: 0.18, ease: [0.23, 1, 0.32, 1] }}
          >
            {children(() => setOpen(false))}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

/** Modal sheet on a native <dialog>: focus trap, Escape and inert background for free. */
export function Sheet({
  open,
  onClose,
  title,
  children,
  wide = false,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
  wide?: boolean;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    if (open && !dialog.open) dialog.showModal();
    if (!open && dialog.open) dialog.close();
  }, [open]);

  return (
    <dialog
      ref={ref}
      className={`sheet${wide ? " sheet-wide" : ""}`}
      aria-label={title}
      onClose={onClose}
      onClick={(e) => e.target === ref.current && onClose()}
    >
      {open && <div className="sheet-body">{children}</div>}
    </dialog>
  );
}
