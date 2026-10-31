/** Small shared primitives: Reminders-style checkbox, duration pill, anchored popover, native-dialog sheet. */

import { Clock3 } from "lucide-react";
import { AnimatePresence, motion } from "motion/react";
import { type CSSProperties, type ReactNode, useEffect, useLayoutEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";

import { formatDuration } from "../lib/dates";

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
    <label className={`checkbox checkbox-${size}`} style={{ "--check": color } as CSSProperties}>
      <input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} aria-label={label} />
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <circle className="ring" cx="12" cy="12" r="10.25" />
        <circle className="fill" cx="12" cy="12" r="11" />
        <path className="mark" d="M7.5 12.4l3 3 6-6.6" />
      </svg>
    </label>
  );
}

/** The reference's dark "◷ 2h" pill. Ink-based: a white pill on a tinted platter would fail contrast. */
export function DurPill({ minutes, label }: { minutes: number; label?: string }) {
  return (
    <span className="dur-pill tabular">
      <Clock3 size={11} strokeWidth={2.5} aria-hidden="true" />
      {label ?? formatDuration(minutes)}
    </span>
  );
}

const GAP = 12;    // between trigger and panel (clears the toolbar capsule)
const MARGIN = 8;  // from the edge of the viewport (or of the dialog that hosts the panel)

/** Pins a fixed panel to its trigger, below it or flipped above when it would not fit.
 *  In a <dialog> the dialog is the containing block (see .sheet), so coordinates are relative to it
 *  and its own box bounds the panel. The far edge (right for "end", bottom when flipped) is the one
 *  pinned, so content that loads later grows away from the trigger. */
function place(anchor: HTMLElement, panel: HTMLElement, host: HTMLElement, align: "start" | "end") {
  const a = anchor.getBoundingClientRect();
  const box = host.tagName === "DIALOG"
    ? host.getBoundingClientRect()
    : new DOMRect(0, 0, window.innerWidth, window.innerHeight);
  const { offsetWidth: w, offsetHeight: h } = panel;
  const below = a.bottom + GAP + h <= box.bottom - MARGIN || a.top - GAP - h < box.top + MARGIN;
  const end = align === "end" ? a.right - w >= box.left + MARGIN : a.left + w > box.right - MARGIN;
  const s = panel.style;
  s.top = below ? `${a.bottom + GAP - box.top}px` : "auto";
  s.bottom = below ? "auto" : `${box.bottom - a.top + GAP}px`;
  s.left = end ? "auto" : `${Math.max(MARGIN, a.left - box.left)}px`;
  s.right = end ? `${Math.max(MARGIN, box.right - a.right)}px` : "auto";
  s.transformOrigin = `${below ? "top" : "bottom"} ${end ? "right" : "left"}`;
}

/** A menu or panel anchored to its trigger. The panel is portalled out of the trigger's subtree so a
 *  glass ancestor (a widget) neither clips it nor traps its blur; inside a modal <dialog> it stays in
 *  the dialog (the rest of the page is inert) and uses the opaque tier, since blurs never nest. */
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
  const [host, setHost] = useState<HTMLElement | null>(null);
  const root = useRef<HTMLDivElement>(null);
  const panel = useRef<HTMLDivElement>(null);
  const openedAt = useRef({ top: 0, left: 0 });

  const toggle = () => {
    if (!open) setHost(root.current?.closest("dialog") ?? document.body);
    setOpen(!open);
  };

  useLayoutEffect(() => {
    const anchor = root.current;
    const el = panel.current;
    if (!open || !host || !anchor || !el) return;
    const update = () => place(anchor, el, host, align);
    const { top, left } = anchor.getBoundingClientRect();
    openedAt.current = { top, left };
    update();
    // keyboard users land in the menu; mouse users see no ring (:focus-visible)
    el.querySelector<HTMLElement>("button, a[href], input")?.focus({ preventScroll: true });
    const resize = new ResizeObserver(update);
    resize.observe(el);
    return () => resize.disconnect();
  }, [open, host, align]);

  useEffect(() => {
    if (!open) return;
    const close = () => setOpen(false);
    const inside = (target: EventTarget | null) =>
      target instanceof Node && (root.current?.contains(target) || panel.current?.contains(target));
    const onPointer = (e: PointerEvent) => {
      if (!inside(e.target)) close();
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== "Escape") return;
      e.preventDefault(); // close the menu, not the sheet around it
      close();
      root.current?.querySelector<HTMLElement>("button")?.focus();
    };
    // scrolling the page, main column or sheet under it closes it (like a macOS menu). Only a scroll
    // that actually moved the trigger counts: scroll events arrive a frame late, so the scroll that
    // brought the trigger into view before the click must not close the menu it opened.
    const onScroll = (e: Event) => {
      const anchor = root.current;
      const target = e.target;
      if (!anchor || !(target === document || (target instanceof Node && target.contains(anchor)))) return;
      const { top, left } = anchor.getBoundingClientRect();
      if (Math.abs(top - openedAt.current.top) > 1 || Math.abs(left - openedAt.current.left) > 1) close();
    };
    document.addEventListener("pointerdown", onPointer);
    document.addEventListener("keydown", onKey);
    document.addEventListener("scroll", onScroll, true);
    window.addEventListener("resize", close);
    return () => {
      document.removeEventListener("pointerdown", onPointer);
      document.removeEventListener("keydown", onKey);
      document.removeEventListener("scroll", onScroll, true);
      window.removeEventListener("resize", close);
    };
  }, [open]);

  const nested = host?.tagName === "DIALOG";
  return (
    <div className="popover-anchor" ref={root}>
      {trigger({ open, toggle })}
      {host &&
        createPortal(
          <AnimatePresence>
            {open && (
              <motion.div
                ref={panel}
                role="dialog"
                aria-label={label}
                className={`popover glass-thick${nested ? " popover-nested" : ""}`}
                initial={{ opacity: 0, transform: "scale(0.96)" }}
                animate={{ opacity: 1, transform: "scale(1)" }}
                exit={{ opacity: 0, transform: "scale(0.98)", transition: { duration: 0.12 } }}
                transition={{ duration: 0.18, ease: [0.23, 1, 0.32, 1] }}
              >
                {children(() => setOpen(false))}
              </motion.div>
            )}
          </AnimatePresence>,
          host,
        )}
    </div>
  );
}

/** Modal sheet on a native <dialog>: focus trap, Escape and inert background for free.
 *  It lives in the top layer, so its glass sees the whole page. */
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
      className={`sheet glass-thick${wide ? " sheet-wide" : ""}`}
      aria-label={title}
      onClose={onClose}
      onClick={(e) => e.target === ref.current && onClose()}
    >
      {open && <div className="sheet-body">{children}</div>}
    </dialog>
  );
}
